require "test_helper"

class AnswerAiAssistantQueryJobTest < ActiveJob::TestCase
  class SuccessfulPipeline
    class << self
      attr_accessor :initialization
    end

    def initialize(**initialization)
      self.class.initialization = initialization
    end

    def execute; end

    def to_response
      {
        results: [],
        result_count: 2,
        answer: {
          answer: "The records show progress.",
          citations: [],
          limitations: []
        }
      }
    end
  end

  class ConfigurationFailurePipeline
    def initialize(**); end

    def execute
      raise Agentic::Errors::ConfigurationError, "Secret provider detail"
    end
  end

  class ExecutionFailurePipeline
    def initialize(**); end

    def execute
      raise Agentic::Errors::ExecutionError, "Temporary provider failure"
    end
  end

  class TransientAnswerJob < AnswerAiAssistantQueryJob
    self.pipeline_class = ExecutionFailurePipeline
    self.llm_connection = Object.new
  end

  test "runs the existing search pipeline and stores the final answer" do
    query = create_query
    job_class = configured_job_class(SuccessfulPipeline)

    broadcasts = capture_turbo_stream_broadcasts([ query.user, query.dependent, :ai_assistant ]) do
      assert_difference -> { PipelineRun.where(subject: query).count }, 1 do
        job_class.perform_now(query)
      end
    end

    query.reload
    pipeline_run = PipelineRun.where(subject: query).order(:id).last
    assert_predicate query, :completed?
    assert_equal "The records show progress.", query.answer_payload[:answer]
    assert_equal 2, query.result_count
    assert_equal "What changed?", pipeline_run.context["query"]
    assert_equal query.id, pipeline_run.context["ai_assistant_query_id"]
    assert_equal pipeline_run.to_global_id.to_s, SuccessfulPipeline.initialization.dig(:context, :pipeline_run_gid)
    assert_equal true, SuccessfulPipeline.initialization[:synthesize_answer]
    assert_equal 2, broadcasts.size
    assert_equal "replace", broadcasts.last["action"]
    assert_includes broadcasts.last.to_html, "PaperBridge Answer"
  end

  test "returns a retryable provider failure to queued and schedules another attempt" do
    query = create_query

    assert_enqueued_with(job: TransientAnswerJob) do
      TransientAnswerJob.perform_now(query)
    end

    assert_predicate query.reload, :queued?
    assert_nil query.failed_at
  end

  test "does not run an already completed query twice" do
    query = create_query
    query.update!(state: :completed, completed_at: Time.current)
    pipeline_class = Class.new do
      def initialize(**)
        raise "provider should not be called"
      end
    end

    assert_no_difference -> { PipelineRun.where(subject: query).count } do
      configured_job_class(pipeline_class).perform_now(query)
    end

    assert_predicate query.reload, :completed?
  end

  test "stores a safe failure when pipeline configuration is invalid" do
    query = create_query
    job_class = configured_job_class(ConfigurationFailurePipeline)

    job_class.perform_now(query)

    query.reload
    assert_predicate query, :failed?
    assert_equal "We couldn’t answer that right now. Please try again in a moment.", query.error_message
    assert_not_includes query.error_message, "Secret provider detail"
  end

  test "does not call the provider after account access is removed" do
    query = create_query
    query.user.account_memberships.where(account: query.account).delete_all
    pipeline_class = Class.new do
      def initialize(**)
        raise "provider should not be called"
      end
    end

    configured_job_class(pipeline_class).perform_now(query)

    assert_predicate query.reload, :failed?
    assert_equal 0, PipelineRun.where(subject: query).count
  end

  private

    def create_query
      AiAssistantQuery.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        question: "What changed?"
      )
    end

    def configured_job_class(pipeline_class)
      Class.new(AnswerAiAssistantQueryJob).tap do |job_class|
        job_class.pipeline_class = pipeline_class
        job_class.llm_connection = Object.new
      end
    end
end
