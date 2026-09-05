require "base64"
require "test_helper"

class ProcessImageDocumentJobTest < ActiveJob::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  class FakeConnection
    class << self
      attr_accessor :requests, :embedding_failure, :metadata_response
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
                }.merge(FakeConnection.metadata_response).to_json
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
    FakeConnection.metadata_response = { category: "prescriptions", description: "An amoxicillin prescription with dosage instructions." }
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
    assert_equal "prescriptions", document.category
    assert_equal "An amoxicillin prescription with dosage instructions.", document.description
    assert_not document.initial_metadata_pending?
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
    assert_includes extraction_payload.dig("response_format", "json_schema", "schema", "required"), "description"
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
    assert_equal 2, FakeConnection.requests.count
  end

  test "initial image metadata completion broadcasts enabled editing fields after the whole extraction transaction" do
    document = create_image_document
    clear_enqueued_jobs

    streams = capture_turbo_stream_broadcasts(document) { ProcessImageDocumentJob.perform_now(document) }
    target = ActionView::RecordIdentifier.dom_id(document, :editable_metadata)
    metadata_streams = streams.select { |stream| stream["target"] == target }

    assert_equal 1, metadata_streams.count
    template = metadata_streams.last.at_css("template")
    assert_nil template.at_css("fieldset[disabled]")
    assert_equal "prescriptions", template.at_css("option[selected]")["value"]
    assert_includes template.text, "An amoxicillin prescription with dosage instructions."
  end

  test "storage-only documents are not enqueued and ignore a directly invoked image job" do
    {
      "record.docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      "record.zip" => "application/zip",
      "record.svg" => "image/svg+xml"
    }.each do |filename, content_type|
      document = nil
      assert_no_enqueued_jobs only: [ ProcessDocumentJob, ProcessImageDocumentJob ] do
        document = create_storage_only_document(filename: filename, content_type: content_type)
      end
      before = document.reload.attributes

      assert_no_difference -> { PipelineRun.count } do
        ProcessImageDocumentJob.perform_now(document)
      end

      assert_equal "stored", document.reload.status
      assert_not document.initial_metadata_pending?
      assert_equal before, document.attributes
      assert_empty document.document_pages
      assert_empty document.document_chunks
      assert_empty document.document_embeddings
      assert_empty FakeConnection.requests
    end
  end

  test "the image job ignores a text document intended for the document pipeline" do
    document = create_storage_only_document(filename: "record.txt", content_type: "text/plain")
    clear_enqueued_jobs
    before = document.reload.attributes

    assert_no_difference -> { PipelineRun.count } do
      ProcessImageDocumentJob.perform_now(document)
    end

    assert_equal before, document.reload.attributes
    assert_empty document.document_pages
    assert_empty FakeConnection.requests
  end

  test "legacy documents retain their category and description with an older response" do
    document = create_image_document(category: :medical, initial_metadata_pending: false)
    document.update!(description: "Original image description.")
    FakeConnection.metadata_response = { category: "prescriptions" }
    clear_enqueued_jobs

    ProcessImageDocumentJob.perform_now(document)

    document.reload
    assert_equal "medical", document.category
    assert_equal "Original image description.", document.description
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

  test "keeps completed metadata and later edits through an image processing retry" do
    document = create_image_document
    clear_enqueued_jobs
    FakeConnection.embedding_failure = true

    assert_enqueued_jobs 1, only: ProcessImageDocumentJob do
      ProcessImageDocumentJob.perform_now(document)
    end

    assert_equal "failed", document.reload.status
    assert_equal "prescriptions", document.category
    assert_equal "An amoxicillin prescription with dosage instructions.", document.description
    assert_not document.initial_metadata_pending?
    document.update!(category: :therapy, description: "My corrected image description.")
    FakeConnection.embedding_failure = false
    FakeConnection.metadata_response = { category: "medical", description: "A different generated image description." }

    ProcessImageDocumentJob.perform_now(document)

    assert_equal "processed", document.reload.status
    assert_equal "therapy", document.category
    assert_equal "My corrected image description.", document.description
    assert_not document.initial_metadata_pending?
  end

  {
    "missing category" => { description: "A generated description." },
    "invalid category" => { category: "not-a-category", description: "A generated description." },
    "missing description" => { category: "prescriptions" },
    "blank description" => { category: "prescriptions", description: "  " }
  }.each do |label, metadata|
    test "leaves image metadata pending and stops before embedding for #{label}" do
      document = create_image_document
      FakeConnection.metadata_response = metadata
      clear_enqueued_jobs

      assert_enqueued_jobs 1, only: ProcessImageDocumentJob do
        ProcessImageDocumentJob.perform_now(document)
      end

      assert_equal "failed", document.reload.status
      assert document.initial_metadata_pending?
      assert_equal "general", document.category
      assert_nil document.description
      assert_empty document.document_chunks
      assert_empty document.document_embeddings
      assert FakeConnection.requests.none? { |request| request.fetch(:url).include?("/embeddings") }
    end
  end

  private

    def create_storage_only_document(filename:, content_type:)
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Stored document",
        category: :general,
        initial_metadata_pending: true,
        file: {
          io: StringIO.new("Stored document bytes"),
          filename: filename,
          content_type: content_type,
          identify: false,
          metadata: { analyzed: true }
        }
      )
    end

    def create_image_document(category: :general, filename: "prescription.png", content_type: "image/png", identify: true, initial_metadata_pending: true)
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Prescription photo",
        category: category,
        initial_metadata_pending: initial_metadata_pending,
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
