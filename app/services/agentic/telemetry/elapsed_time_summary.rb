# frozen_string_literal: true

module Agentic
  module Telemetry
    class ElapsedTimeSummary
      include LogEntries

      LLM_EVENT_TYPE = "llm_call"

      def initialize(pipeline_run, by_agent: false)
        @pipeline_run = pipeline_run
        @by_agent = by_agent
      end

      def call
        calls = elapsed_calls

        elapsed_time = {
          total_elapsed_ms: total_elapsed_ms(calls),
          total_stream_callback_elapsed_ms: total_stream_callback_elapsed_ms(calls),
          llm_call_count: calls.count
        }
        elapsed_time[:calls] = calls if by_agent?

        { elapsed_time: elapsed_time }
      end

      private

      attr_reader :pipeline_run

      def by_agent?
        @by_agent
      end

      def elapsed_calls
        log_entries_for(LLM_EVENT_TYPE).map do |entry|
          payload = entry.fetch("payload", {}).to_h.symbolize_keys
          call = payload.slice(:model, :elapsed_ms, :stream_callback_elapsed_ms)
          call[:stream_callback_elapsed_ms] ||= 0

          call.merge(agent: entry.fetch("agent"))
        end
      end

      def total_elapsed_ms(calls)
        calls.sum { |call| call[:elapsed_ms].to_i }
      end

      def total_stream_callback_elapsed_ms(calls)
        calls.sum { |call| call[:stream_callback_elapsed_ms].to_i }
      end
    end
  end
end
