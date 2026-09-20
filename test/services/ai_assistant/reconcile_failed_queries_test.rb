require "test_helper"

class AiAssistant::ReconcileFailedQueriesTest < ActionDispatch::IntegrationTest
  class InterruptedPipeline
    def initialize(context:, **)
      @run = GlobalID::Locator.locate(context.fetch(:pipeline_run_gid))
    end

    def execute
      @run.mark_processing!
      throw :worker_stopped, :interrupted
    end
  end

  setup do
    capture_io { load Rails.root.join("db/queue_schema.rb") }
    SolidQueue::Record.descendants.each(&:reset_column_information)
    @query = AiAssistantQuery.create!(
      account: accounts(:greenfield), dependent: dependents(:emma),
      user: users(:family_admin), question: "What should we discuss at the meeting?"
    )
    @active_job = AnswerAiAssistantQueryJob.new(@query)
    @query.update!(answer_job_id: @active_job.job_id, enqueued_at: Time.current)
    @job = SolidQueue::Job.enqueue(@active_job)
    @worker = SolidQueue::Process.register(kind: "Worker", name: "query-recovery-test", pid: 123, hostname: "test", metadata: {})
  end

  test "a lost worker releases a processing question so the user can ask again" do
    claimed = claim_job
    original_pipeline = AnswerAiAssistantQueryJob.pipeline_class
    begin
      AnswerAiAssistantQueryJob.pipeline_class = InterruptedPipeline
      assert_equal :interrupted, catch(:worker_stopped) { claimed.perform }
    ensure
      AnswerAiAssistantQueryJob.pipeline_class = original_pipeline
    end
    assert_predicate @query.reload, :processing?
    run = @query.pipeline_runs.last
    assert_equal @job.id, run.context.fetch("processing_job_id")
    claimed.failed_with(SolidQueue::Processes::ProcessMissingError.new)

    assert_no_enqueued_jobs do
      assert_equal 1, ReconcileAiAssistantQueriesJob.perform_now
    end
    assert_predicate @query.reload, :failed?
    assert_nil @query.draft_answer
    assert_predicate run.reload, :failed?
    assert_equal 0, AiAssistant::ReconcileFailedQueries.call

    sign_in @query.user
    get status_dependent_ai_assistant_query_path(@query.dependent, @query)
    assert_response :success
    assert_select "[data-query-id='#{@query.id}'][data-active='false']"
    assert_includes response.body, "Please ask your question again."

    assert_difference "AiAssistantQuery.count", 1 do
      post dependent_ai_assistant_path(@query.dependent), params: { q: "A new question" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_select "[data-active='true']"
    assert_includes response.body, "A new question"
  end

  test "a worker lost before execution is recovered without relying on a started timestamp" do
    claim_job.failed_with(SolidQueue::Processes::ProcessMissingError.new)
    assert_nil @query.started_at

    assert_equal 1, AiAssistant::ReconcileFailedQueries.call

    assert_predicate @query.reload, :failed?
    assert_empty @query.pipeline_runs
  end

  test "a scheduled retry stays active and a worker failure on the later attempt can be recovered" do
    claim_job.failed_with(SolidQueue::Processes::ProcessMissingError.new)
    retry_job = AnswerAiAssistantQueryJob.new(@query)
    retry_job.job_id = @active_job.job_id
    next_attempt = SolidQueue::Job.enqueue(retry_job, scheduled_at: 1.minute.from_now)
    assert_equal @job.active_job_id, next_attempt.active_job_id
    assert_not_equal @job.id, next_attempt.id

    assert_equal 0, AiAssistant::ReconcileFailedQueries.call
    assert_predicate @query.reload, :queued?

    # The earlier attempt is historical; only the later worker now fails.
    @job.failed_execution.destroy!
    @job.finished!
    next_attempt.scheduled_execution.destroy!
    next_attempt.failed_with(SolidQueue::Processes::ProcessMissingError.new)

    assert_equal 1, AiAssistant::ReconcileFailedQueries.call
    assert_predicate @query.reload, :failed?
  end

  test "an old failure cannot overwrite a completed answer or a manual queue retry" do
    claim_job.failed_with(SolidQueue::Processes::ProcessMissingError.new)
    @job.failed_execution.retry

    assert_equal 0, AiAssistant::ReconcileFailedQueries.call
    assert_predicate @query.reload, :queued?

    @job.reload.blocked_execution.destroy!
    @job.failed_with(SolidQueue::Processes::ProcessMissingError.new)
    @query.update!(state: :completed, answer: { answer: "Keep this completed answer." }, completed_at: Time.current)
    before = @query.attributes

    assert_equal 0, AiAssistant::ReconcileFailedQueries.call
    assert_equal before, @query.reload.attributes
  end

  private

    def claim_job
      SolidQueue::ReadyExecution.claim("ai_assistant", 1, @worker.id).first
    end
end
