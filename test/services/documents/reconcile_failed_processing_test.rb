require "test_helper"

class Documents::ReconcileFailedProcessingTest < ActiveSupport::TestCase
  setup do
    create_queue_tables
    @document = documents(:advance_directive)
    @document.file.attach(
      io: StringIO.new("The original uploaded document."), filename: "source.txt", content_type: "text/plain",
      metadata: { analyzed: true }
    )
    clear_enqueued_jobs
  end

  test "reconciles a proven pruned worker while retaining the original file and generated evidence" do
    execution, run = failed_processing
    @document.update!(
      summary: { summary: "A completed summary.", key_points: [ "Keep this evidence." ] },
      summarized_at: 2.days.ago, prepared_payload: { full_text: "Already extracted text." }
    )
    chunk = @document.document_chunks.first
    chunk.document_embeddings.create!(
      provider: DocumentEmbedding::PROVIDER, model: DocumentEmbedding::MODEL,
      dimensions: DocumentEmbedding::DIMENSIONS, distance_metric: DocumentEmbedding::DISTANCE_METRIC,
      embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001)
    )
    chunk.timeline_events.create!(
      event_type: "observation", title: "Existing event", description: "Preserve the extracted event.",
      date_precision: "unknown", date_source: "undated", source_quote: chunk.content, content_hash: "existing-event"
    )
    document_before = @document.reload.attributes.except("status", "preparation_error", "updated_at")
    records_before = evidence_snapshot
    original_blob_id = @document.file.blob_id
    queue_record_before = execution.attributes

    assert_no_difference [ "Document.count", "PipelineRun.count", "AiAssistantQuery.count" ] do
      assert_no_enqueued_jobs do
        assert_equal 1, ReconcileDocumentProcessingJob.perform_now
      end
    end

    assert_predicate @document.reload, :failed?
    assert_equal Documents::ReconcileFailedProcessing::FAILURE_MESSAGE, @document.preparation_error
    assert_equal document_before, @document.attributes.except("status", "preparation_error", "updated_at")
    assert_equal records_before, evidence_snapshot
    assert_equal original_blob_id, @document.file.blob_id
    assert_equal "The original uploaded document.", @document.file.download
    assert_predicate run.reload, :failed?
    assert_predicate run.failed_at, :present?
    assert_equal queue_record_before, execution.reload.attributes

    unchanged = @document.attributes
    assert_equal 0, Documents::ReconcileFailedProcessing.call
    assert_equal unchanged, @document.reload.attributes
  end

  test "reconciles a proven image worker exit during preparation without inventing a summary" do
    status = Struct.new(:pid, :exitstatus, :termsig) do
      def signaled?
        termsig.present?
      end
    end.new(123, nil, 9)
    _execution, run = failed_processing(
      job_class: ProcessImageDocumentJob,
      error: SolidQueue::Processes::ProcessExitError.new(status),
      preparation_status: :preparing
    )
    @document.update!(initial_metadata_pending: true)

    assert_equal 1, Documents::ReconcileFailedProcessing.call

    assert_predicate @document.reload, :failed?
    assert_predicate @document, :preparation_failed?
    assert_predicate @document, :initial_metadata_pending?
    assert_equal({}, @document.summary)
    assert_nil @document.summarized_at
    assert_predicate run.reload, :failed?
  end

  test "reconciles an orphaned claimed job when Solid Queue records its process as missing" do
    _execution, run = failed_processing(error: SolidQueue::Processes::ProcessMissingError.new)

    assert_equal 1, Documents::ReconcileFailedProcessing.call

    assert_predicate @document.reload, :failed?
    assert_predicate run.reload, :failed?
  end

  test "only fails active pipeline runs belonging to this document and queue job" do
    execution, current_run = failed_processing
    pending_run = PipelineRun.create!(subject: @document, state: :pending, context: { processing_job_id: execution.job_id })
    previous_run = PipelineRun.create!(subject: @document, state: :processing, context: { processing_job_id: execution.job_id + 1 })
    completed_run = PipelineRun.create!(subject: @document, state: :completed, context: { processing_job_id: execution.job_id })
    other_run = PipelineRun.create!(
      subject: documents(:outside_account), state: :processing, context: { processing_job_id: execution.job_id }
    )
    unchanged_runs = [ previous_run, completed_run, other_run ].map(&:attributes)

    assert_equal 1, Documents::ReconcileFailedProcessing.call

    assert_predicate current_run.reload, :failed?
    assert_predicate pending_run.reload, :failed?
    assert_equal unchanged_runs, [ previous_run, completed_run, other_run ].map { |run| run.reload.attributes }
  end

  test "an old failed queue job cannot overwrite a newer attempt with the same Active Job id" do
    execution, run = failed_processing
    old_job = execution.job
    new_job = create_queue_job(@document, active_job_id: old_job.active_job_id)
    @document.update!(processing_job_id: new_job.id)
    before = @document.attributes

    assert_equal 0, Documents::ReconcileFailedProcessing.call

    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?
  end

  test "does not overwrite a completed document or a queued retry" do
    _execution, run = failed_processing

    %i[processed queued].each do |status|
      @document.update!(status: status)
      before = @document.attributes

      assert_equal 0, Documents::ReconcileFailedProcessing.call

      assert_equal before, @document.reload.attributes
      assert_predicate run.reload, :processing?
    end
  end

  test "ordinary application failures are not treated as dead workers" do
    _execution, run = failed_processing(error: Agentic::Errors::ConfigurationError.new("Missing configuration"))
    before = @document.attributes

    assert_equal 0, Documents::ReconcileFailedProcessing.call

    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?
  end

  test "a long-running document without an actual failed execution remains processing" do
    job = create_queue_job(@document)
    @document.update!(status: :processing, processing_job_id: job.id)
    @document.update_columns(updated_at: 1.year.ago)
    before = @document.attributes

    assert_equal 0, Documents::ReconcileFailedProcessing.call

    assert_equal before, @document.reload.attributes
  end

  test "legacy documents without a recorded queue id require separate verified reconciliation" do
    _execution, run = failed_processing
    @document.update!(processing_job_id: nil)
    before = @document.attributes

    assert_equal 0, Documents::ReconcileFailedProcessing.call

    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?
  end

  test "does not act on a failure that was removed for a manual Solid Queue retry" do
    execution, run = failed_processing
    SolidQueue::FailedExecution.where(id: execution.id).delete_all
    before = @document.attributes

    assert_equal 0, Documents::ReconcileFailedProcessing.new.send(:reconcile, execution)

    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?
  end

  test "ignores unrelated job classes and a job whose arguments identify another document" do
    _execution, run = failed_processing(job_class: AnswerAiAssistantQueryJob)
    before = @document.attributes
    assert_equal 0, Documents::ReconcileFailedProcessing.call
    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?

    execution, run = failed_processing(argument_document: documents(:outside_account))
    before = @document.attributes
    assert_equal 0, Documents::ReconcileFailedProcessing.call
    assert_equal before, @document.reload.attributes
    assert_predicate run.reload, :processing?
    assert_predicate execution, :persisted?
  end

  test "ignores a source document deleted before reconciliation" do
    execution, _run = failed_processing
    @document.destroy!
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      assert_equal 0, Documents::ReconcileFailedProcessing.call
    end

    assert_not Document.exists?(@document.id)
    assert SolidQueue::FailedExecution.exists?(execution.id)
  end

  private

    def failed_processing(job_class: ProcessDocumentJob, error: nil, preparation_status: :prepared, argument_document: @document)
      job = create_queue_job(argument_document, job_class: job_class)
      execution = SolidQueue::FailedExecution.create!(
        job: job, exception: error || SolidQueue::Processes::ProcessPrunedError.new(2.minutes.ago)
      )
      @document.update!(status: :processing, preparation_status: preparation_status, processing_job_id: job.id)
      run = PipelineRun.create!(subject: @document, user: @document.user, state: :processing, context: { processing_job_id: job.id })
      [ execution, run ]
    end

    def create_queue_job(document, job_class: ProcessDocumentJob, active_job_id: nil)
      arguments = job_class.new(document).serialize
      arguments["job_id"] = active_job_id if active_job_id
      id = SolidQueue::Job.insert_all!([ {
        active_job_id: arguments.fetch("job_id"), class_name: job_class.name, arguments: arguments,
        queue_name: "default", priority: 0, created_at: Time.current, updated_at: Time.current
      } ]).first.fetch("id")
      SolidQueue::Job.find(id)
    end

    def evidence_snapshot
      [ @document.document_pages, @document.document_chunks, @document.document_embeddings, @document.timeline_events ]
        .map { |records| records.order(:id).map(&:attributes) }
    end

    def create_queue_tables
      # Tests use one primary database. These two queue tables exist only inside
      # this test's transaction, so the real Solid Queue models and row locks run
      # without touching the development queue database.
      connection = SolidQueue::Record.connection
      unless connection.table_exists?(:solid_queue_jobs)
        connection.create_table :solid_queue_jobs do |table|
          table.string :active_job_id
          table.text :arguments
          table.string :class_name, null: false
          table.string :concurrency_key
          table.datetime :finished_at
          table.integer :priority, default: 0, null: false
          table.string :queue_name, null: false
          table.datetime :scheduled_at
          table.timestamps
        end
      end
      unless connection.table_exists?(:solid_queue_failed_executions)
        connection.create_table :solid_queue_failed_executions do |table|
          table.datetime :created_at, null: false
          table.text :error
          table.bigint :job_id, null: false, index: { unique: true }
        end
      end
      SolidQueue::Job.reset_column_information
      SolidQueue::FailedExecution.reset_column_information
    end
end
