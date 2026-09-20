require "test_helper"

class Documents::ResetProcessingTest < ActiveSupport::TestCase
  setup do
    @document = documents(:advance_directive)
    @document.file.attach(io: StringIO.new("Original document"), filename: "source.txt", content_type: "text/plain", metadata: { analyzed: true })
    @document.update!(
      status: :failed, title: "My title", category: :therapy, description: "My description",
      initial_metadata_pending: false, preparation_status: :prepared,
      prepared_payload: { full_text: "Stale extraction" }, prepared_at: 2.days.ago,
      preparation_error: "Previous error", summary: { summary: "Stale summary", key_points: [ "Stale point" ] }, summarized_at: 2.days.ago
    )
    @page = @document.document_pages.first
    @page.image.attach(io: StringIO.new("Generated page image"), filename: "page.png", content_type: "image/png", metadata: { analyzed: true })
    @chunk = @document.document_chunks.first
    @chunk.document_embeddings.create!(
      provider: DocumentEmbedding::PROVIDER, model: DocumentEmbedding::MODEL,
      dimensions: DocumentEmbedding::DIMENSIONS, distance_metric: DocumentEmbedding::DISTANCE_METRIC,
      embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001)
    )
    @chunk.timeline_events.create!(
      event_type: "observation", title: "Old event", description: "Old generated event",
      date_precision: "unknown", date_source: "undated", source_quote: "Old source quote", content_hash: "old-event"
    )
    clear_enqueued_jobs
  end

  test "clears generated results while preserving the original metadata research sharing and history" do
    create_research_and_history
    preserved_models = [ AiAssistantQuery, SavedAnswer, MeetingPrep, MeetingPrepAnswer, ShareEvent, SharedDocument, PipelineRun, PipelineLog, PipelineActivity ]
    before = preserved_models.map { |model| model.order(:id).map(&:attributes) }
    metadata = @document.attributes.except(*reset_attribute_names)
    original_blob = @document.file.blob
    generated_blob = @page.image.blob

    assert Documents::ResetProcessing.call(@document, processing_job_id: 42)

    @document.reload
    assert_equal metadata, @document.attributes.except(*reset_attribute_names)
    assert_equal before, preserved_models.map { |model| model.order(:id).map(&:attributes) }
    assert_equal original_blob, @document.file.blob
    assert_equal "Original document", @document.file.download
    assert_empty @document.document_pages
    assert_empty @document.document_chunks
    assert_empty @document.document_embeddings
    assert_empty @document.timeline_events
    assert_equal({}, @document.summary)
    assert_equal({}, @document.prepared_payload)
    assert_nil @document.summarized_at
    assert_nil @document.prepared_at
    assert_nil @document.preparation_error
    assert_predicate @document, :processing?
    assert_predicate @document, :unprepared?
    assert_equal 42, @document.processing_job_id
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [ generated_blob ])
    assert_equal @document, SavedAnswer.last.source_documents_by_id.fetch(@document.id)
  end

  test "image cleanup never purges the original shared upload" do
    @page.image.attach(@document.file.blob)
    clear_enqueued_jobs
    original_blob = @document.file.blob

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      assert Documents::ResetProcessing.call(@document)
    end
    assert ActiveStorage::Blob.exists?(original_blob.id)
    assert_equal original_blob.id, @document.reload.file.blob_id
    assert_equal "Original document", @document.file.download
    assert_empty @document.document_pages
  end

  test "pending initial metadata remains pending for the fresh pipeline to generate" do
    @document.update!(initial_metadata_pending: true)
    assert Documents::ResetProcessing.call(@document)
    assert_predicate @document.reload, :initial_metadata_pending?
  end

  test "a reset failure rolls back generated record deletion and does not purge attachments" do
    @document.update_column(:title, "")
    before = @document.attributes
    embedding_ids = @document.document_embeddings.ids
    event_ids = @document.timeline_events.ids

    assert_no_enqueued_jobs(only: ActiveStorage::PurgeJob) do
      assert_raises(ActiveRecord::RecordInvalid) { Documents::ResetProcessing.call(@document) }
    end
    assert_equal before, @document.reload.attributes
    assert DocumentPage.exists?(@page.id)
    assert DocumentChunk.exists?(@chunk.id)
    assert_equal embedding_ids, @document.document_embeddings.ids
    assert_equal event_ids, @document.timeline_events.ids
    assert_predicate @page.reload.image, :attached?
  end

  test "only the same identified job can reset a running document and no job can reset a completed document" do
    [
      [ :processing, 10, 11 ],
      [ :processing, nil, nil ],
      [ :processed, 10, 10 ]
    ].each do |status, current_job_id, attempted_job_id|
      @document.update!(status: status, processing_job_id: current_job_id)
      before = @document.attributes
      assert_no_enqueued_jobs { assert_not Documents::ResetProcessing.call(@document, processing_job_id: attempted_job_id) }
      assert_equal before, @document.reload.attributes
      assert DocumentChunk.exists?(@chunk.id)
    end
  end

  private

    def reset_attribute_names
      %w[status processing_job_id preparation_status prepared_payload prepared_at preparation_error summary summarized_at updated_at]
    end

    def create_research_and_history
      query = AiAssistantQuery.create!(
        account: @document.account, dependent: @document.dependent, user: @document.user,
        state: :completed, question: "What should I discuss?", completed_at: 1.day.ago,
        answer: { answer: "Keep this saved research", citations: [ { document_id: @document.id, page_number: 1, quote: "Keep this quote" } ] }
      )
      answer = SavedAnswer.save_from_query!(query)
      answer.update!(notes: "My preparation notes")
      prep = MeetingPrep.create!(account: @document.account, dependent: @document.dependent, user: @document.user, name: "Meeting")
      prep.meeting_prep_answers.create!(saved_answer: answer, position: 1)
      run = @document.pipeline_runs.create!(user: @document.user, state: :failed, message: "Original failure")
      run.append_log(agent: "DocumentSummarizer", message: "Original failure", payload: {})
      run.append_activity(action: "failed", message: "Original failure")
      clear_enqueued_jobs
    end
end
