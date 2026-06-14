# frozen_string_literal: true

require "bigdecimal"

module Agentic
  module Telemetry
    class PricingSummary
      include LogEntries

      LLM_EVENT_TYPE = "llm_call"

      def initialize(pipeline_run, by_agent: false)
        @pipeline_run = pipeline_run
        @by_agent = by_agent
      end

      def call
        calls = priced_calls

        pricing = {
          total_cost: rounded_cost(total_cost(calls)),
          llm_call_count: calls.count
        }
        pricing[:calls] = calls.map { |call| rounded_call(call) } if by_agent?

        { pricing: pricing }
      end

      private

      attr_reader :pipeline_run

      def by_agent?
        @by_agent
      end

      def priced_calls
        log_entries_for(LLM_EVENT_TYPE).map { |entry| priced_call(entry) }
      end

      def priced_call(entry)
        payload = entry.fetch("payload", {}).to_h.symbolize_keys

        payload.slice(:provider, :model, :input_tokens, :cached_input_tokens, :output_tokens).merge(
          agent: entry.fetch("agent"),
          cost: payload.empty? ? BigDecimal("0") : Agentic::LlmCallPricing.estimate(payload)
        )
      end

      def total_cost(calls)
        calls.sum(BigDecimal("0")) { |call| call[:cost] }
      end

      def rounded_call(call)
        call.merge(cost: rounded_cost(call[:cost]))
      end

      def rounded_cost(cost)
        cost.round(4).to_f
      end
    end
  end
end
