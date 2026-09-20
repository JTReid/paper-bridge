# frozen_string_literal: true

module AiAssistant
  class ReconcileFailedQueries
    WORKER_FAILURE_CLASSES = %w[
      SolidQueue::Processes::ProcessPrunedError
      SolidQueue::Processes::ProcessExitError
      SolidQueue::Processes::ProcessMissingError
    ].freeze
    FAILURE_MESSAGE = "Your answer was interrupted. Please ask your question again."

    def self.call
      new.call
    end

    def call
      reconciled_count = 0

      AiAssistantQuery.where(state: %w[queued processing]).where.not(answer_job_id: nil).in_batches(of: 100) do |queries|
        SolidQueue::FailedExecution.joins(:job)
          .where(solid_queue_jobs: { class_name: "AnswerAiAssistantQueryJob", active_job_id: queries.pluck(:answer_job_id) })
          .where("solid_queue_failed_executions.error::jsonb ->> 'exception_class' IN (?)", WORKER_FAILURE_CLASSES)
          .find_each do |execution|
            reconciled_count += reconcile(execution)
          end
      end

      reconciled_count
    end

    private

      def reconcile(execution)
        # A manual Solid Queue retry locks and removes this same failure row.
        execution.with_lock do
          return 0 unless WORKER_FAILURE_CLASSES.include?(execution.exception_class)

          job = execution.job
          return 0 unless job.class_name == "AnswerAiAssistantQueryJob"

          query = AiAssistantQuery.find_by(answer_job_id: job.active_job_id)
          return 0 unless query && job.arguments.dig("arguments", 0, "_aj_globalid") == query.to_global_id.to_s

          query.with_lock do
            return 0 unless query.active? && query.answer_job_id == job.active_job_id
            return 0 if pending_attempt?(query)

            query.assign_attributes(
              state: :failed, answer: {}, draft_answer: nil, failed_at: Time.current,
              completed_at: nil, error_message: FAILURE_MESSAGE
            )
            query.save!(validate: false)
            query.pipeline_runs.where(state: %w[pending processing])
              .where("context->>'processing_job_id' = ?", job.id.to_s).find_each do |run|
                run.mark_failed!(message: FAILURE_MESSAGE)
              end
          end

          Rails.logger.warn("ai_assistant_worker_failed query_id=#{query.id} queue_job_id=#{job.id} error_class=#{execution.exception_class}")
          1
        end
      rescue ActiveRecord::RecordNotFound
        0
      end

      def pending_attempt?(query)
        # Automatic Active Job retries retain their UUID but get a new queue row.
        SolidQueue::Job.where(active_job_id: query.answer_job_id, class_name: "AnswerAiAssistantQueryJob", finished_at: nil)
          .where.missing(:failed_execution).exists?
      end
  end
end
