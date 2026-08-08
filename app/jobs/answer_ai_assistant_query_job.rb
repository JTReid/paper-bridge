# frozen_string_literal: true

class AnswerAiAssistantQueryJob < ApplicationJob
  queue_as :ai_assistant

  class_attribute :llm_connection, default: RestClient
  class_attribute :pipeline_class, default: Agentic::DocumentSearchPipeline

  limits_concurrency key: ->(query) { query }, duration: 10.minutes
  retry_on Agentic::Errors::ExecutionError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    job.send(:mark_failed, job.arguments.first)
  end
  discard_on ActiveJob::DeserializationError

  def perform(ai_assistant_query)
    return if ai_assistant_query.completed?
    return mark_failed(ai_assistant_query) unless authorized_for_execution?(ai_assistant_query)

    ai_assistant_query.update!(
      state: :processing,
      started_at: ai_assistant_query.started_at || Time.current,
      completed_at: nil,
      failed_at: nil,
      error_message: nil
    )

    pipeline_run = PipelineRun.create!(
      subject: ai_assistant_query,
      user: ai_assistant_query.user,
      context: pipeline_run_context(ai_assistant_query)
    )
    pipeline = pipeline_class.new(
      context: pipeline_context(ai_assistant_query, pipeline_run),
      connection: llm_connection,
      synthesize_answer: true
    )

    pipeline.execute
    response = pipeline.to_response

    ai_assistant_query.update!(
      state: :completed,
      answer: response[:answer] || {},
      result_count: response[:result_count].to_i,
      completed_at: Time.current,
      failed_at: nil,
      error_message: nil
    )
  rescue Agentic::Errors::ConfigurationError => e
    Rails.logger.error(
      "paperbridge_answer_failed query_id=#{ai_assistant_query.id} " \
        "error_class=#{e.class.name} error_message=#{e.message.to_s.squish}"
    )
    mark_failed(ai_assistant_query)
  rescue Agentic::Errors::ExecutionError => e
    Rails.logger.warn(
      "paperbridge_answer_retrying query_id=#{ai_assistant_query.id} " \
        "error_class=#{e.class.name} error_message=#{e.message.to_s.squish}"
    )
    mark_queued(ai_assistant_query)
    raise
  rescue StandardError
    mark_failed(ai_assistant_query)
    raise
  end

  private

    def pipeline_run_context(ai_assistant_query)
      {
        query: ai_assistant_query.question,
        ai_assistant_query_id: ai_assistant_query.id,
        account_id: ai_assistant_query.account_id,
        dependent_id: ai_assistant_query.dependent_id
      }
    end

    def authorized_for_execution?(ai_assistant_query)
      ai_assistant_query.dependent.account_id == ai_assistant_query.account_id &&
        ai_assistant_query.user.account_memberships.exists?(account_id: ai_assistant_query.account_id)
    end

    def pipeline_context(ai_assistant_query, pipeline_run)
      {
        pipeline_run_gid: pipeline_run.to_global_id.to_s,
        account_gid: ai_assistant_query.account.to_global_id.to_s,
        actor_gid: ai_assistant_query.user.to_global_id.to_s,
        dependent_gid: ai_assistant_query.dependent.to_global_id.to_s,
        query: ai_assistant_query.question,
        access_profile: Documents::SearchAccessProfile.for(
          ai_assistant_query.user,
          account: ai_assistant_query.account,
          dependent: ai_assistant_query.dependent
        ),
        limit: 10
      }
    end

    def mark_failed(ai_assistant_query)
      return unless ai_assistant_query&.persisted?

      ai_assistant_query.assign_attributes(
        state: :failed,
        answer: {},
        failed_at: Time.current,
        completed_at: nil,
        error_message: "We couldn’t answer that right now. Please try again in a moment."
      )
      ai_assistant_query.save!(validate: false)
    end

    def mark_queued(ai_assistant_query)
      return unless ai_assistant_query&.persisted?

      ai_assistant_query.update!(
        state: :queued,
        completed_at: nil,
        failed_at: nil,
        error_message: nil
      )
    end
end
