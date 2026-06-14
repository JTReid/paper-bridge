# frozen_string_literal: true

module Agentic
  module Providers
    module LlmCallTelemetry
      attr_reader :elapsed_ms, :raw_response

      def llm_metadata
        {
          provider: provider_name,
          model: requirements[:model],
          operation_type: operation_type.to_s,
          elapsed_ms: elapsed_ms
        }.merge(token_usage).merge(raw_usage: raw_usage)
      end

      def failure_metadata(error)
        metadata = llm_metadata.merge(
          status: "failed",
          error_class: error.class.name,
          error_message: error.message
        )

        metadata[:http_code] = error.http_code if error.respond_to?(:http_code)
        metadata
      end

      private

      def measure_api_call
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        yield
      ensure
        @elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
      end

      def token_usage
        raise NotImplementedError, "#{self.class.name} must implement #token_usage"
      end

      def raw_usage
        raise NotImplementedError, "#{self.class.name} must implement #raw_usage"
      end

      def token_total(*counts)
        values = counts.compact
        return nil if values.empty?

        values.sum
      end
    end
  end
end
