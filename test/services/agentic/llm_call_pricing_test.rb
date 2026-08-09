# frozen_string_literal: true

require "test_helper"

class Agentic::LlmCallPricingTest < ActiveSupport::TestCase
  test "prices Luna GPT-5.6 input and output usage" do
    cost = Agentic::LlmCallPricing.estimate(
      provider: "openai",
      model: "gpt-5.6-luna",
      input_tokens: 1_000_000,
      cached_input_tokens: 250_000,
      output_tokens: 1_000_000
    )

    assert_equal BigDecimal("1.40"), cost
  end

  test "does not claim an exact price when required usage is unavailable" do
    cost = Agentic::LlmCallPricing.estimate_if_available(
      provider: "openai",
      model: "gpt-5.6-luna",
      input_tokens: nil,
      output_tokens: nil
    )

    assert_nil cost
  end

  test "requires cached usage when cached and regular input rates differ" do
    cost = Agentic::LlmCallPricing.estimate_if_available(
      provider: "openai",
      model: "gpt-5.4",
      input_tokens: 1_000_000,
      cached_input_tokens: nil,
      output_tokens: 100_000
    )

    assert_nil cost
  end

  test "prices embeddings without cached usage because that operation is not cached" do
    cost = Agentic::LlmCallPricing.estimate_if_available(
      provider: "openai",
      model: "text-embedding-3-large",
      input_tokens: 1_000_000,
      cached_input_tokens: nil,
      output_tokens: nil
    )

    assert_equal BigDecimal("0.13"), cost
  end
end
