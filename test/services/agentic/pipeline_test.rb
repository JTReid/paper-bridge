# frozen_string_literal: true

require "test_helper"

module AgenticPipelineTestAgents
  class BaseAgent
    attr_reader :data

    def initialize(data = {})
      @data = data
    end

    def step_started
      "#{self.class.name} started"
    end

    def step_complete
      "#{self.class.name} complete"
    end

    def pass_through_pipeline_response?
      false
    end
  end

  class FirstAgent < BaseAgent
    def execute
      "#{data.fetch(:content)} first"
    end
  end

  class ContextAgent < BaseAgent
    def execute
      "#{data.fetch(:content)} #{data.fetch(:context).fetch(:suffix)}"
    end
  end

  class RejectingValidator < BaseAgent
    def execute
      { status: "REJECTED" }
    end

    def pass_through_pipeline_response?
      true
    end
  end

  class FailingAgent < BaseAgent
    def execute
      raise "boom"
    end
  end

  class Pipeline < Agentic::Pipeline
    def initialize(context:)
      super(
        [
          [ FirstAgent, { after_execute: after_first }, { tag: :first } ],
          [ ContextAgent, {}, { tag: :context } ]
        ],
        context: context
      )
    end

    def to_response
      results.last&.result
    end

    private

    def after_first
      ->(result, context, _content) { context[:suffix] = result }
    end
  end

  class RejectedPipeline < Agentic::Pipeline
    def initialize(context:)
      super(
        [
          [ FirstAgent, {}, { tag: :first } ],
          [ RejectingValidator, {}, { tag: :validator } ],
          [ ContextAgent, {}, { tag: :context } ]
        ],
        context: context
      )
    end

    def to_response
      results.last&.result
    end
  end

  class FailedPipeline < Agentic::Pipeline
    def initialize(context:)
      super([ [ FailingAgent, {}, { tag: :failure } ] ], context: context)
    end

    def to_response
      nil
    end
  end
end

class Agentic::PipelineTest < ActiveSupport::TestCase
  test "requires a pipeline run global id" do
    error = assert_raises(Agentic::Errors::ConfigurationError) do
      AgenticPipelineTestAgents::Pipeline.new(context: {})
    end

    assert_equal "context[:pipeline_run_gid] is required", error.message
  end

  test "runs agents in order and shares callback context" do
    pipeline_run = PipelineRun.create!(user: users(:family_admin))
    pipeline = AgenticPipelineTestAgents::Pipeline.new(context: { pipeline_run_gid: pipeline_run.to_global_id.to_s })

    pipeline.execute("source")

    assert pipeline.valid?
    assert_equal "source first source first", pipeline.to_response
    assert_equal "completed", pipeline_run.reload.state
    assert_equal %w[started completed], pipeline_run.pipeline_activity.entries.pluck("action").values_at(0, -1)
    assert_includes pipeline_run.pipeline_log.entries.pluck("message"), "Step 1 completed"
    assert_includes pipeline_run.pipeline_log.entries.pluck("message"), "Step 2 completed"
  end

  test "validator rejection stops later agents and still completes the run" do
    pipeline_run = PipelineRun.create!
    pipeline = AgenticPipelineTestAgents::RejectedPipeline.new(context: { pipeline_run_gid: pipeline_run.to_global_id.to_s })

    pipeline.execute("source")

    assert_not pipeline.valid?
    assert_equal 2, pipeline.results.count
    assert_equal "completed", pipeline_run.reload.state
  end

  test "agent errors mark the run failed" do
    pipeline_run = PipelineRun.create!
    pipeline = AgenticPipelineTestAgents::FailedPipeline.new(context: { pipeline_run_gid: pipeline_run.to_global_id.to_s })

    error = assert_raises(Agentic::Errors::ExecutionError) do
      pipeline.execute("source")
    end

    assert_equal "boom", error.message
    assert_equal "failed", pipeline_run.reload.state
    assert_includes pipeline_run.pipeline_log.entries.pluck("message"), "Pipeline execution failed"
  end
end
