# frozen_string_literal: true

require "bigdecimal"

module Agentic
  class LlmCallPricing
    TOKENS_PER_MILLION = BigDecimal("1000000")

    RATE_CARD = {
      "openai:gpt-5.4" => {
        input_per_million: BigDecimal("2.50"),
        cached_input_per_million: BigDecimal("0.25"),
        output_per_million: BigDecimal("15.00")
      },
      "openai:gpt-5.4-mini" => {
        input_per_million: BigDecimal("0.75"),
        cached_input_per_million: BigDecimal("0.075"),
        output_per_million: BigDecimal("4.50")
      },
      "openai:gpt-5.4-nano" => {
        input_per_million: BigDecimal("0.20"),
        cached_input_per_million: BigDecimal("0.02"),
        output_per_million: BigDecimal("1.25")
      },
      "openai:gpt-5.4nano" => {
        input_per_million: BigDecimal("0.20"),
        cached_input_per_million: BigDecimal("0.02"),
        output_per_million: BigDecimal("1.25")
      }
    }.freeze

    def self.estimate(call)
      new(call).estimate
    end

    def initialize(call)
      @call = call
    end

    def estimate
      input_cost + cached_input_cost + output_cost
    end

    private

    attr_reader :call

    def rate
      @rate ||= RATE_CARD.fetch(model_key, zero_rate)
    end

    def model_key
      @model_key ||= [ call.fetch(:provider), call.fetch(:model) ].map { |value| value.to_s.downcase }.join(":")
    end

    def input_cost
      token_cost(non_cached_input_tokens, rate.fetch(:input_per_million))
    end

    def cached_input_cost
      token_cost(cached_input_tokens, rate.fetch(:cached_input_per_million))
    end

    def output_cost
      token_cost(output_tokens, rate.fetch(:output_per_million))
    end

    def non_cached_input_tokens
      input_tokens - cached_input_tokens
    end

    def input_tokens
      call[:input_tokens].to_i
    end

    def cached_input_tokens
      call[:cached_input_tokens].to_i
    end

    def output_tokens
      call[:output_tokens].to_i
    end

    def token_cost(tokens, rate_per_million)
      BigDecimal(tokens.to_s) * rate_per_million / TOKENS_PER_MILLION
    end

    def zero_rate
      {
        input_per_million: BigDecimal("0"),
        cached_input_per_million: BigDecimal("0"),
        output_per_million: BigDecimal("0")
      }
    end
  end
end
