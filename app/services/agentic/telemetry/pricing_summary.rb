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
        calls = llm_calls
        priced_calls = calls.select { |call| call[:cost_available] }

        pricing = {
          total_cost: rounded_cost(total_cost(priced_calls)),
          llm_call_count: calls.count,
          priced_llm_call_count: priced_calls.count,
          unpriced_llm_call_count: calls.count - priced_calls.count,
          cost_complete: priced_calls.count == calls.count
        }
        pricing[:calls] = calls.map { |call| rounded_call(call) } if by_agent?

        { pricing: pricing }
      end

      private

      attr_reader :pipeline_run

      def by_agent?
        @by_agent
      end

      def llm_calls
        log_entries_for(LLM_EVENT_TYPE).map { |entry| llm_call(entry) }
      end

      def llm_call(entry)
        payload = entry.fetch("payload", {}).to_h.symbolize_keys
        cost = Agentic::LlmCallPricing.estimate_if_available(payload)

        payload.slice(:provider, :model, :input_tokens, :cached_input_tokens, :output_tokens).merge(
          agent: entry.fetch("agent"),
          cost: cost,
          cost_available: !cost.nil?
        )
      end

      def total_cost(calls)
        calls.sum(BigDecimal("0")) { |call| call[:cost] }
      end

      def rounded_call(call)
        return call if call[:cost].nil?

        call.merge(cost: rounded_cost(call[:cost]))
      end

      def rounded_cost(cost)
        cost.round(4).to_f
      end
    end
  end
end
