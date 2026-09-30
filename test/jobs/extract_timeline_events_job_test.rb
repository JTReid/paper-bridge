require "base64"
require "test_helper"

class ExtractTimelineEventsJobTest < ActiveJob::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )
  CHUNK_CONTENT = "Speech and language evaluation completed on July 21, 2023."

  def self.timeline_event(document_chunk_id, **overrides)
    {
      document_chunk_id: document_chunk_id,
      event_type: "evaluation",
      title: "Speech evaluation",
      description: "A speech and language evaluation was completed.",
      occurred_on: "2023-07-21",
      started_on: "",
      ended_on: "",
      date_precision: "exact",
      date_source: "explicit",
      source_quote: CHUNK_CONTENT
    }.merge(overrides)
  end

  class FakeConnection
    class << self
      attr_accessor :requests, :content, :before_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.requests << kwargs
        FakeConnection.before_request&.call
        payload = JSON.parse(kwargs.fetch(:payload))

        unless payload.dig("response_format", "json_schema", "name") == "timeline_events"
          raise "Unexpected timeline test request: #{kwargs.fetch(:url)}"
        end

        {
          choices: [
            {
              message: {
                content: FakeConnection.content || timeline_content(payload)
              }
            }
          ],
          usage: {
            prompt_tokens: 40,
            completion_tokens: 30,
            total_tokens: 70
          }
        }.to_json
      end

      def self.timeline_content(payload)
        chunk_id = payload.dig("messages", 1, "content")[/document_chunk_id:\s*(\d+)/, 1].to_i

        { events: [ ExtractTimelineEventsJobTest.timeline_event(chunk_id) ] }.to_json
      end
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = ExtractTimelineEventsJob.llm_connection
    FakeConnection.requests = []
    FakeConnection.content = nil
    FakeConnection.before_request = nil
    ExtractTimelineEventsJob.llm_connection = FakeConnection
  end

  teardown do
    ExtractTimelineEventsJob.llm_connection = @original_connection
  end

  test "extracts timeline events in its own pipeline run without changing the document" do
    document = create_processed_document
    before = document.reload.attributes

    assert_difference -> { PipelineRun.count } do
      ExtractTimelineEventsJob.perform_now(document)
    end

    pipeline_run = document.pipeline_runs.last
    event = document.timeline_events.sole
    payload = JSON.parse(FakeConnection.requests.sole.fetch(:payload))

    assert_equal before, document.reload.attributes
    assert_equal "evaluation", event.event_type
    assert_equal Date.new(2023, 7, 21), event.occurred_on
    assert_equal document.document_chunks.sole, event.document_chunk
    assert_equal "completed", pipeline_run.state
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "timeline_events_extracted" }
    assert_equal "gpt-5.4-mini", payload.fetch("model")
    assert_not_includes payload.dig("messages", 1, "content"), Agents::TimelineEventExtractor::IMAGE_GUIDANCE
  end

  test "a failed extraction retries only the timeline and leaves the document processed" do
    document = create_processed_document
    FakeConnection.content = "not json"

    assert_enqueued_with(job: ExtractTimelineEventsJob, args: [ document ]) do
      ExtractTimelineEventsJob.perform_now(document)
    end

    assert_predicate document.reload, :processed?
    assert_nil document.preparation_error
    assert_empty document.timeline_events
    assert_equal "failed", document.pipeline_runs.last.state
  end

  test "a malformed event is skipped without losing the valid events" do
    document = create_processed_document
    chunk_id = document.document_chunks.sole.id
    FakeConnection.content = {
      events: [
        self.class.timeline_event(chunk_id),
        self.class.timeline_event(
          chunk_id,
          event_type: "therapy",
          title: "Weekly speech therapy",
          occurred_on: "",
          started_on: "2024-09-01",
          ended_on: "2024-06-01",
          date_precision: "range"
        )
      ]
    }.to_json

    ExtractTimelineEventsJob.perform_now(document)

    assert_equal [ "Speech evaluation" ], document.timeline_events.pluck(:title)
    assert_equal "completed", document.pipeline_runs.last.state
  end

  test "skips documents that are not processed" do
    %i[queued processing failed].each do |status|
      document = create_processed_document
      document.update!(status: status)

      assert_no_difference -> { PipelineRun.count } do
        ExtractTimelineEventsJob.perform_now(document)
      end
    end

    assert_empty FakeConnection.requests
  end

  test "image documents get stricter guidance against routine paperwork events" do
    document = create_processed_document(image: true, category: :medical)

    ExtractTimelineEventsJob.perform_now(document)

    payload = JSON.parse(FakeConnection.requests.sole.fetch(:payload))
    assert_includes payload.dig("messages", 1, "content"), Agents::TimelineEventExtractor::IMAGE_GUIDANCE
    assert_equal 1, document.timeline_events.count
  end

  test "skips prescription images but not prescription PDFs or insurance images" do
    document = create_processed_document(image: true, category: :prescriptions)

    assert_no_difference -> { PipelineRun.count } do
      ExtractTimelineEventsJob.perform_now(document)
    end
    assert_empty FakeConnection.requests

    ExtractTimelineEventsJob.perform_now(create_processed_document(category: :prescriptions))
    ExtractTimelineEventsJob.perform_now(create_processed_document(image: true, category: :insurance))

    assert_equal 2, FakeConnection.requests.count
  end

  test "discards the job quietly when the document is deleted during extraction" do
    document = create_processed_document
    FakeConnection.before_request = -> { Document.find_by(id: document.id)&.destroy! }

    assert_nothing_raised do
      ExtractTimelineEventsJob.perform_now(document)
      perform_enqueued_jobs only: ExtractTimelineEventsJob
    end

    assert_not Document.exists?(document.id)
    assert_equal 0, PipelineRun.where(subject_type: "Document", subject_id: document.id).count
    assert_no_enqueued_jobs only: ExtractTimelineEventsJob
  end

  test "discards the job quietly and leaves no run when the document is deleted before extraction starts" do
    document = create_processed_document
    Document.find(document.id).destroy!

    assert_nothing_raised { ExtractTimelineEventsJob.perform_now(document) }

    assert_equal 0, PipelineRun.where(subject_type: "Document", subject_id: document.id).count
    assert_empty FakeConnection.requests
    assert_no_enqueued_jobs only: ExtractTimelineEventsJob
  end

  private

    def create_processed_document(image: false, category: :medical)
      document = Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Speech evaluation",
        category: category,
        file: image ? image_file : text_file
      )
      page = document.document_pages.create!(account: document.account, page_number: 1, status: :processed)
      document.document_chunks.create!(
        account: document.account,
        document_page: page,
        content: CHUNK_CONTENT,
        content_hash: DocumentChunk.content_hash_for(CHUNK_CONTENT),
        label: "medical",
        chunk_index: 1
      )
      document.update!(status: :processed, preparation_status: :prepared)
      clear_enqueued_jobs
      document
    end

    def text_file
      { io: StringIO.new(CHUNK_CONTENT), filename: "evaluation.txt", content_type: "text/plain" }
    end

    def image_file
      { io: StringIO.new(ONE_BY_ONE_PNG), filename: "evaluation.png", content_type: "image/png" }
    end
end
