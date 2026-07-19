require "base64"
require "test_helper"

class ProcessImageDocumentJobTest < ActiveJob::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  class FakeConnection
    class << self
      attr_accessor :requests, :embedding_failure
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.requests << kwargs
        payload = JSON.parse(kwargs.fetch(:payload))

        if kwargs.fetch(:url).include?("/embeddings")
          return failed_embedding_response(payload) if FakeConnection.embedding_failure

          return embedding_response(payload)
        end
        return extraction_response if schema_name(payload) == "image_document_extraction"

        raise "Unexpected image document test request: #{kwargs.fetch(:url)}"
      end

      def self.extraction_response
        {
          choices: [
            {
              message: {
                content: {
                  extracted_text: "Amoxicillin 500 mg. Take one capsule twice daily. Dr. Rivera.",
                  category: "prescriptions",
                  summary: "A prescription for amoxicillin with handwritten dosage instructions.",
                  key_points: [
                    "Amoxicillin 500 mg",
                    "Take one capsule twice daily"
                  ],
                  search_chunks: [
                    {
                      content: "Prescription for Amoxicillin 500 mg.",
                      label: "medical"
                    },
                    {
                      content: "Directions: Take one capsule twice daily. Prescriber: Dr. Rivera.",
                      label: "medical"
                    }
                  ]
                }.to_json
              }
            }
          ],
          usage: {
            prompt_tokens: 100,
            completion_tokens: 80,
            total_tokens: 180
          }
        }.to_json
      end

      def self.embedding_response(payload)
        inputs = Array(payload.fetch("input"))

        {
          data: inputs.each_with_index.map do |_input, index|
            {
              object: "embedding",
              index: index,
              embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001)
            }
          end,
          model: payload.fetch("model"),
          usage: {
            prompt_tokens: 16,
            total_tokens: 16
          }
        }.to_json
      end

      def self.failed_embedding_response(payload)
        {
          data: [],
          model: payload.fetch("model"),
          usage: {
            prompt_tokens: 0,
            total_tokens: 0
          }
        }.to_json
      end

      def self.schema_name(payload)
        payload.dig("response_format", "json_schema", "name")
      end
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = ProcessImageDocumentJob.llm_connection
    FakeConnection.requests = []
    FakeConnection.embedding_failure = false
    ProcessImageDocumentJob.llm_connection = FakeConnection
  end

  teardown do
    ProcessImageDocumentJob.llm_connection = @original_connection
    FakeConnection.embedding_failure = false
  end

  test "extracts, classifies, chunks, and embeds an image document" do
    document = create_image_document
    original_blob = document.file.blob
    clear_enqueued_jobs

    assert_difference -> { PipelineRun.count } do
      ProcessImageDocumentJob.perform_now(document)
    end

    document.reload
    page = document.document_pages.first
    pipeline_run = document.pipeline_runs.last
    extraction_request = request_for_schema("image_document_extraction")
    extraction_payload = JSON.parse(extraction_request.fetch(:payload))
    embedding_request = FakeConnection.requests.find { |request| request.fetch(:url).include?("/embeddings") }
    embedding_payload = JSON.parse(embedding_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "image-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal "image", document.prepared_payload.fetch("format")
    assert_equal 1, document.prepared_payload.fetch("page_count")
    assert_equal "Amoxicillin 500 mg. Take one capsule twice daily. Dr. Rivera.", document.prepared_payload.fetch("extracted_text")
    assert_equal document.prepared_payload.fetch("extracted_text"), document.prepared_payload.fetch("full_text")
    assert_equal "general", document.category
    assert_equal "prescriptions", document.prepared_payload.dig("classification", "detected_category")
    assert_not document.prepared_payload.fetch("classification").key?("applied_category")
    assert_equal 1, document.document_pages.count
    assert_equal "processed", page.status
    assert_equal document.prepared_payload.fetch("extracted_text"), page.ocr_text
    assert page.image.attached?
    assert_equal original_blob.id, page.image.blob.id
    assert_equal 2, document.document_chunks.count
    assert_equal 2, document.document_embeddings.count
    assert_equal [ "medical", "medical" ], document.document_chunks.map(&:label)
    assert_equal "A prescription for amoxicillin with handwritten dosage instructions.", document.summary.fetch("summary")
    assert_equal [ "Amoxicillin 500 mg", "Take one capsule twice daily" ], document.summary.fetch("key_points")
    assert_equal "image_document_extractor", document.summary.dig("metadata", "source")
    assert_equal "prescriptions", document.summary.dig("metadata", "detected_category")
    assert_not document.summary.fetch("metadata").key?("applied_category")
    assert document.summarized_at.present?
    assert_empty document.timeline_events
    assert_equal "completed", pipeline_run.state

    assert_equal "gpt-5.4-mini", extraction_payload.fetch("model")
    user_content = extraction_payload.dig("messages", 1, "content")
    assert_kind_of Array, user_content
    assert_includes user_content.first.fetch("text"), "including printed and handwritten text"
    image_content = user_content.find { |part| part.fetch("type") == "image_url" }
    assert_match %r{\Adata:image/png;base64,}, image_content.dig("image_url", "url")
    assert_equal "high", image_content.dig("image_url", "detail")

    assert_equal "text-embedding-3-large", embedding_payload.fetch("model")
    assert_equal document.document_chunks.map(&:content), embedding_payload.fetch("input")
    assert pipeline_run.pipeline_log.entries.any? { |entry| entry["event_type"] == "llm_call" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "image_document_extracted" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "document_chunks_embedded" }
  end

  test "retains GPT classification as metadata without changing the document category" do
    document = create_image_document(category: :medical)
    clear_enqueued_jobs

    ProcessImageDocumentJob.perform_now(document)

    document.reload
    assert_equal "medical", document.category
    assert_equal "prescriptions", document.prepared_payload.dig("classification", "detected_category")
    assert_not document.prepared_payload.fetch("classification").key?("applied_category")
    assert_equal "prescriptions", document.summary.dig("metadata", "detected_category")
    assert_not document.summary.fetch("metadata").key?("applied_category")
  end

  test "final Turbo summary broadcast retains the extracted summary" do
    document = create_image_document
    clear_enqueued_jobs

    turbo_streams = capture_turbo_stream_broadcasts(document) do
      ProcessImageDocumentJob.perform_now(document)
    end
    summary_target = ActionView::RecordIdentifier.dom_id(document, :summary)
    summary_broadcasts = turbo_streams.select { |stream| stream["target"] == summary_target }

    assert_operator summary_broadcasts.count, :>=, 2
    final_summary_html = summary_broadcasts.last.at_css("template").inner_html
    assert_includes final_summary_html, "A prescription for amoxicillin with handwritten dosage instructions."
    assert_includes final_summary_html, "Ready"
    assert_not_includes final_summary_html, "A summary isn’t available yet."
  end

  test "preserves the extracted summary when embedding fails" do
    document = create_image_document
    clear_enqueued_jobs
    FakeConnection.embedding_failure = true

    turbo_streams = capture_turbo_stream_broadcasts(document) do
      assert_enqueued_jobs 1, only: ProcessImageDocumentJob do
        ProcessImageDocumentJob.perform_now(document)
      end
    end

    document.reload
    pipeline_run = document.pipeline_runs.last
    summary_target = ActionView::RecordIdentifier.dom_id(document, :summary)
    final_summary_html = turbo_streams
      .select { |stream| stream["target"] == summary_target }
      .last
      .at_css("template")
      .inner_html

    assert_equal "failed", document.status
    assert_equal "prepared", document.preparation_status
    assert_includes document.preparation_error, "Embedding response count did not match chunk count"
    assert_equal "A prescription for amoxicillin with handwritten dosage instructions.", document.summary.fetch("summary")
    assert_equal [ "Amoxicillin 500 mg", "Take one capsule twice daily" ], document.summary.fetch("key_points")
    assert document.summarized_at.present?
    assert_equal "Amoxicillin 500 mg. Take one capsule twice daily. Dr. Rivera.", document.prepared_payload.fetch("extracted_text")
    assert_equal 2, document.document_chunks.count
    assert_equal 0, document.document_embeddings.count
    assert_equal "failed", pipeline_run.state
    assert_includes final_summary_html, "A prescription for amoxicillin with handwritten dosage instructions."
    assert_includes final_summary_html, "Needs attention"
    assert_not_includes final_summary_html, "We couldn’t prepare a summary for this file."
  end

  test "fails closed when an image bypasses intake normalization" do
    document = create_image_document(
      filename: "prescription.tiff",
      content_type: "image/tiff",
      identify: false
    )
    clear_enqueued_jobs
    FakeConnection.requests = []

    assert_no_difference -> { PipelineRun.count } do
      ProcessImageDocumentJob.perform_now(document)
    end

    document.reload
    assert_equal "failed", document.status
    assert_equal "preparation_failed", document.preparation_status
    assert_includes document.preparation_error, "was not normalized before processing"
    assert_empty FakeConnection.requests
  end

  private

    def create_image_document(category: :general, filename: "prescription.png", content_type: "image/png", identify: true)
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Prescription photo",
        category: category,
        file: {
          io: StringIO.new(ONE_BY_ONE_PNG),
          filename: filename,
          content_type: content_type,
          identify: identify
        }
      )
    end

    def request_for_schema(schema_name)
      FakeConnection.requests.find do |request|
        next false unless request.fetch(:url).include?("/chat/completions")

        JSON.parse(request.fetch(:payload)).dig("response_format", "json_schema", "name") == schema_name
      end
    end
end
