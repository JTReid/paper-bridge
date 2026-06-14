# frozen_string_literal: true

module Agentic
  class PipelineInstrumentation
    def initialize(pipeline_run:, pipeline_name:)
      @pipeline_run = pipeline_run
      @pipeline_name = pipeline_name
    end

    def run_started(total_steps:)
      @pipeline_run.mark_processing!(message: "Pipeline execution started")
      append_log(
        agent: @pipeline_name,
        message: "Pipeline execution started",
        payload: { total_steps: total_steps }
      )
      append_activity(action: "started", message: "Pipeline execution started")
    end

    def run_completed
      @pipeline_run.mark_completed!(message: "Pipeline execution completed successfully")
      append_log(agent: @pipeline_name, message: "Pipeline execution completed", payload: {})
      append_activity(action: "completed", message: "Pipeline execution completed")
    end

    def run_failed(error:)
      @pipeline_run.mark_failed!(message: error.message)
      append_log(
        agent: @pipeline_name,
        message: "Pipeline execution failed",
        payload: {
          error_class: error.class.name,
          error_message: error.message
        }
      )
      append_activity(action: "failed", message: "Pipeline execution failed")
    end

    def step_completed(agent_class, index:, tag:)
      append_log(
        agent: agent_class.name,
        message: "Step #{index + 1} completed",
        payload: step_payload(tag: tag)
      )
    end

    def step_failed(agent_class, index:, tag:, error:)
      payload = step_payload(tag: tag).merge(
        error_class: error.class.name,
        error_message: error.message
      )

      if error.respond_to?(:http_code)
        payload[:http_code] = error.http_code
        payload[:response_body] = error.response&.body&.truncate(1000)
      end

      append_log(
        agent: agent_class.name,
        message: "Step #{index + 1} failed: #{error.class}",
        payload: payload
      )
    end

    def log_event(agent_class, message:, payload: {}, event_type: nil)
      append_log(
        agent: agent_class.is_a?(Class) ? agent_class.name : agent_class.to_s,
        message: message,
        payload: payload || {},
        event_type: event_type
      )
    end

    private

    def append_log(agent:, message:, payload:, event_type: nil)
      @pipeline_run.append_log(agent: agent, message: message, payload: payload, event_type: event_type)
    end

    def append_activity(action:, message:, metadata: {})
      @pipeline_run.append_activity(action: action, message: message, metadata: metadata)
    end

    def step_payload(tag:)
      {}.tap do |payload|
        payload[:tag] = tag if tag
      end
    end
  end
end
