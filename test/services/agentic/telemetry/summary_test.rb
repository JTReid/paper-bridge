# frozen_string_literal: true

require "test_helper"

class Agentic::Telemetry::SummaryTest < ActiveSupport::TestCase
  test "summarizes llm pricing and elapsed time from pipeline logs" do
    pipeline_run = PipelineRun.create!
    pipeline_run.append_log(
      agent: "Agents::Example",
      message: "LLM call completed",
      event_type: "llm_call",
      payload: {
        provider: "openai",
        model: "gpt-5.4-nano",
        input_tokens: 1_000,
        cached_input_tokens: 200,
        output_tokens: 100,
        elapsed_ms: 250
      }
    )

    summary = pipeline_run.telemetry_summary(by_agent: true)

    assert_equal 1, summary.fetch(:pricing).fetch(:llm_call_count)
    assert_equal 1, summary.fetch(:pricing).fetch(:priced_llm_call_count)
    assert_equal 0, summary.fetch(:pricing).fetch(:unpriced_llm_call_count)
    assert_equal true, summary.fetch(:pricing).fetch(:cost_complete)
    assert_equal 0.0003, summary.fetch(:pricing).fetch(:total_cost)
    assert_equal 250, summary.fetch(:elapsed_time).fetch(:total_elapsed_ms)
    assert_equal 0, summary.fetch(:elapsed_time).fetch(:total_stream_callback_elapsed_ms)
    assert_equal "Agents::Example", summary.fetch(:pricing).fetch(:calls).first.fetch(:agent)
    legacy_elapsed_call = summary.fetch(:elapsed_time).fetch(:calls).first
    assert_equal 0, legacy_elapsed_call.fetch(:stream_callback_elapsed_ms)
  end

  test "reports local stream callback time without changing request wall time" do
    pipeline_run = PipelineRun.create!
    pipeline_run.append_log(
      agent: "Agents::StreamingExample",
      message: "LLM call completed",
      event_type: "llm_call",
      payload: {
        provider: "openai",
        model: "gpt-5.6-luna",
        input_tokens: 10,
        output_tokens: 5,
        elapsed_ms: 1_000,
        stream_callback_elapsed_ms: 150
      }
    )

    elapsed_time = pipeline_run.telemetry_summary(by_agent: true).fetch(:elapsed_time)

    assert_equal 1_000, elapsed_time.fetch(:total_elapsed_ms)
    assert_equal 150, elapsed_time.fetch(:total_stream_callback_elapsed_ms)
    assert_equal 150, elapsed_time.fetch(:calls).first.fetch(:stream_callback_elapsed_ms)
  end

  test "keeps known totals while reporting calls with unavailable usage as unpriced" do
    pipeline_run = PipelineRun.create!
    pipeline_run.append_log(
      agent: "Agents::KnownUsage",
      message: "LLM call completed",
      event_type: "llm_call",
      payload: {
        provider: "openai",
        model: "gpt-5.6-luna",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      }
    )
    pipeline_run.append_log(
      agent: "Agents::MissingUsage",
      message: "LLM call failed",
      event_type: "llm_call",
      payload: {
        provider: "openai",
        model: "gpt-5.6-luna",
        input_tokens: nil,
        cached_input_tokens: nil,
        output_tokens: nil
      }
    )

    pricing = pipeline_run.telemetry_summary(by_agent: true).fetch(:pricing)

    assert_equal 2, pricing.fetch(:llm_call_count)
    assert_equal 1, pricing.fetch(:priced_llm_call_count)
    assert_equal 1, pricing.fetch(:unpriced_llm_call_count)
    assert_equal false, pricing.fetch(:cost_complete)
    assert_equal 1.4, pricing.fetch(:total_cost)
    known_call, unknown_call = pricing.fetch(:calls)
    assert_equal true, known_call.fetch(:cost_available)
    assert_equal 1.4, known_call.fetch(:cost)
    assert_equal false, unknown_call.fetch(:cost_available)
    assert_nil unknown_call.fetch(:cost)
  end

  test "prices older usage logs that do not include cached token counts" do
    pipeline_run = PipelineRun.create!
    pipeline_run.append_log(
      agent: "Agents::OlderLog",
      message: "LLM call completed",
      event_type: "llm_call",
      payload: {
        provider: "openai",
        model: "gpt-5.6-luna",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      }
    )

    pricing = pipeline_run.telemetry_summary.fetch(:pricing)

    assert_equal 1, pricing.fetch(:priced_llm_call_count)
    assert_equal 0, pricing.fetch(:unpriced_llm_call_count)
    assert_equal true, pricing.fetch(:cost_complete)
    assert_equal 1.4, pricing.fetch(:total_cost)
  end
end
