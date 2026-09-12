# frozen_string_literal: true

module Documents
  class ReconcileFailedProcessing
    PROCESSING_JOB_CLASSES = %w[ProcessDocumentJob ProcessImageDocumentJob].freeze
    WORKER_FAILURE_CLASSES = %w[
      SolidQueue::Processes::ProcessPrunedError
      SolidQueue::Processes::ProcessExitError
      SolidQueue::Processes::ProcessMissingError
    ].freeze
    FAILURE_MESSAGE = "Document processing stopped unexpectedly. Your original file is still available."

    def self.call
      new.call
    end

    def call
      reconciled_count = 0

      Document.processing.where.not(processing_job_id: nil).in_batches(of: 100) do |documents|
        failed_executions(documents.pluck(:processing_job_id)).find_each do |execution|
          reconciled_count += reconcile(execution)
        end
      end

      reconciled_count
    end

    private

      def failed_executions(job_ids)
        SolidQueue::FailedExecution.joins(:job)
          .where(job_id: job_ids, solid_queue_jobs: { class_name: PROCESSING_JOB_CLASSES })
          .where("solid_queue_failed_executions.error::jsonb ->> 'exception_class' IN (?)", WORKER_FAILURE_CLASSES)
      end

      def reconcile(execution)
        # Solid Queue deletes this row before a manual retry is dispatched.
        # Lock it so an old failure cannot be applied after that retry starts.
        execution.with_lock do
          return 0 unless WORKER_FAILURE_CLASSES.include?(execution.exception_class)

          job = execution.job
          return 0 unless PROCESSING_JOB_CLASSES.include?(job.class_name)

          document = Document.processing.find_by(processing_job_id: execution.job_id)
          return 0 unless document
          return 0 unless job.arguments.dig("arguments", 0, "_aj_globalid") == document.to_global_id.to_s

          document.with_lock do
            return 0 unless document.processing? && document.processing_job_id == execution.job_id

            document.update!(
              status: :failed,
              preparation_status: document.prepared? ? :prepared : :preparation_failed,
              preparation_error: FAILURE_MESSAGE
            )
            document.pipeline_runs.where(state: %w[pending processing])
              .where("context->>'processing_job_id' = ?", execution.job_id.to_s).find_each do |run|
                run.mark_failed!(message: FAILURE_MESSAGE)
              end
          end

          Rails.logger.warn("document_processing_worker_failed document_id=#{document.id} queue_job_id=#{execution.job_id} error_class=#{execution.exception_class}")
          1
        end
      rescue ActiveRecord::RecordNotFound
        # The failed execution was retried/discarded, or the document was deleted.
        0
      end
  end
end
