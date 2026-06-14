# frozen_string_literal: true

module Agentic
  class PipelineContext
    attr_reader :shared

    def initialize(context, instrumentation:)
      @shared = (context || {}).dup
      @instrumentation = instrumentation
    end

    def prepare_for_agent(agent_params, agent_class)
      provided = (agent_params.delete(:context) || {}).deep_symbolize_keys

      @shared.merge!(provided)
      @shared[:log_event] = build_log_callback(agent_class) unless provided.key?(:log_event)
    end

    def to_params(content, agent_params)
      { content: content, context: @shared }.merge(agent_params)
    end

    private

    def build_log_callback(agent_class)
      lambda do |message:, payload: {}, event_type: nil|
        @instrumentation.log_event(agent_class, message: message, payload: payload, event_type: event_type)
      end
    end
  end
end
