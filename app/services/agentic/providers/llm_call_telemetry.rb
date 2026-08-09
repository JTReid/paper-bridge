# frozen_string_literal: true

module Agentic
  module Providers
    module LlmCallTelemetry
      attr_reader :elapsed_ms, :raw_response, :stream_callback_elapsed_ms

      def llm_metadata
        {
          provider: provider_name,
          model: requirements[:model],
          operation_type: operation_type.to_s,
          elapsed_ms: elapsed_ms,
          stream_callback_elapsed_ms: stream_callback_elapsed_ms
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
        @stream_callback_elapsed_seconds = 0.0
        started_at = monotonic_time

        yield
      ensure
        elapsed_seconds = monotonic_time - started_at
        @elapsed_ms = (elapsed_seconds * 1000).round
        @stream_callback_elapsed_ms = (@stream_callback_elapsed_seconds * 1000).round
      end

      def measure_stream_callback
        started_at = monotonic_time

        yield
      ensure
        @stream_callback_elapsed_seconds += monotonic_time - started_at
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
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
