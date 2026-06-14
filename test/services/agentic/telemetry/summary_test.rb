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
    assert_equal 0.0003, summary.fetch(:pricing).fetch(:total_cost)
    assert_equal 250, summary.fetch(:elapsed_time).fetch(:total_elapsed_ms)
    assert_equal "Agents::Example", summary.fetch(:pricing).fetch(:calls).first.fetch(:agent)
  end
end
