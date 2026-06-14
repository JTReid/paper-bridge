# frozen_string_literal: true

module Agentic
  module Instrumented
    def log_event(message, payload = {}, event_type: nil)
      logger = logging_context[:log_event]
      return unless logger

      logger.call(message: message, payload: payload || {}, event_type: event_type)
    end

    def log_activity(action:, message:, metadata: {})
      gid = logging_context[:pipeline_run_gid]
      pipeline_run = GlobalID::Locator.locate(gid)

      pipeline_run&.append_activity(action: action, message: message, metadata: metadata)
    end

    private

    def logging_context
      if respond_to?(:context)
        context || {}
      elsif respond_to?(:data)
        data[:context] || {}
      else
        {}
      end
    end
  end
end
