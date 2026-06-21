require "base64"
require "test_helper"

class ProcessDocumentJobTest < ActiveJob::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  class FakeConnection
    class << self
      attr_accessor :requests

      def last_request
        requests.last
      end
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.requests << kwargs
        payload = JSON.parse(kwargs.fetch(:payload))

        return embedding_response(payload) if kwargs.fetch(:url).include?("/embeddings")
        return timeline_response(payload) if schema_name(payload) == "timeline_events"
        return chunk_response(payload) if schema_name(payload) == "document_chunks"

        raise "Unexpected process document test request: #{kwargs.fetch(:url)}"
      end

      def self.chunk_response(payload)
        text = text_content(payload)
        label = text.include?("IEP") || text.include?("PDF") ? "education" : "legal"

        {
          choices: [
            {
              message: {
                content: {
                  chunks: [
                    {
                      content: "Chunk created from #{text.include?("OCR PDF") ? "PDF" : "text"} content.",
                      label: label
                    }
                  ]
                }.to_json
              }
            }
          ],
          usage: {
            prompt_tokens: 30,
            completion_tokens: 20,
            total_tokens: 50
          }
        }.to_json
      end

      def self.timeline_response(payload)
        chunk_id = text_content(payload)[/document_chunk_id:\s*(\d+)/, 1].to_i

        {
          choices: [
            {
              message: {
                content: {
                  events: [
                    {
                      document_chunk_id: chunk_id,
                      event_type: "evaluation",
                      title: "Uploaded document reviewed",
                      description: "The uploaded document was processed as evidence.",
                      occurred_on: "2023-07-21",
                      started_on: "",
                      ended_on: "",
                      date_precision: "exact",
                      date_source: "explicit",
                      source_quote: "Chunk created from text content."
                    }
                  ]
                }.to_json
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
            prompt_tokens: 12,
            total_tokens: 12
          }
        }.to_json
      end

      def self.schema_name(payload)
        payload.dig("response_format", "json_schema", "name")
      end

      def self.text_content(payload)
        content = payload.dig("messages", 1, "content")
        return content.to_s unless content.is_a?(Array)

        content.select { |part| part["type"] == "text" }.map { |part| part["text"] }.join("\n")
      end
    end
  end

  class FakePdfCommandRunner
    def page_count(_pdf_path)
      1
    end

    def extract_text(_pdf_path, page_number:)
      "Embedded PDF page #{page_number}"
    end

    def render_page(_pdf_path, page_number:, output_dir:, dpi:)
      path = File.join(output_dir, "page-#{page_number}.png")
      File.binwrite(path, ONE_BY_ONE_PNG)
      path
    end

    def ocr_image(_image_path)
      "OCR PDF page text"
    end
  end

  class FakeImageOnlyPdfCommandRunner < FakePdfCommandRunner
    def extract_text(_pdf_path, page_number:)
      ""
    end

    def ocr_image(_image_path)
      ""
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = ProcessDocumentJob.llm_connection
    @original_pdf_command_runner = ProcessDocumentJob.pdf_command_runner
    FakeConnection.requests = []
    ProcessDocumentJob.llm_connection = FakeConnection
  end

  teardown do
    ProcessDocumentJob.llm_connection = @original_connection
    ProcessDocumentJob.pdf_command_runner = @original_pdf_command_runner
  end

  test "prepares the file, creates chunks, embeds them, and marks the document processed" do
    document = create_document
    clear_enqueued_jobs

    assert_difference -> { PipelineRun.count } do
      ProcessDocumentJob.perform_now(document)
    end

    document.reload
    pipeline_run = document.pipeline_runs.last
    chunk_request = chat_request_for("document_chunks")
    timeline_request = chat_request_for("timeline_events")
    embedding_request = FakeConnection.requests.find { |request| request.fetch(:url).include?("/embeddings") }
    chunk_payload = JSON.parse(chunk_request.fetch(:payload))
    timeline_payload = JSON.parse(timeline_request.fetch(:payload))
    embedding_payload = JSON.parse(embedding_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "text-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal 1, document.document_pages.count
    assert_equal 1, document.document_chunks.count
    assert_equal 1, document.document_embeddings.count
    assert_equal 1, document.timeline_events.count
    assert_equal "legal", document.document_chunks.first.label
    assert_equal "text-embedding-3-large", document.document_embeddings.first.model
    assert_equal 3_072, document.document_embeddings.first.dimensions
    assert_equal "evaluation", document.timeline_events.first.event_type
    assert_equal document.document_chunks.first, document.timeline_events.first.document_chunk
    assert_equal "completed", pipeline_run.state
    assert_equal "gpt-5.4-nano", chunk_payload.fetch("model")
    assert_equal "gpt-5.4-mini", timeline_payload.fetch("model")
    assert_equal "text-embedding-3-large", embedding_payload.fetch("model")
    assert_includes chunk_payload.dig("messages", 1, "content").first.fetch("text"), "This is the uploaded test document."
    assert_includes timeline_payload.dig("messages", 1, "content"), "document_chunk_id: #{document.document_chunks.first.id}"
    assert_equal [ document.document_chunks.first.content ], embedding_payload.fetch("input")
    assert pipeline_run.pipeline_log.entries.any? { |entry| entry["event_type"] == "llm_call" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "document_chunked" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "document_chunks_embedded" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "timeline_events_extracted" }
  end

  test "prepares PDFs before chunking and embedding them" do
    ProcessDocumentJob.pdf_command_runner = FakePdfCommandRunner.new
    document = create_pdf_document
    clear_enqueued_jobs

    ProcessDocumentJob.perform_now(document)

    document.reload
    chunk_request = chat_request_for("document_chunks")
    payload = JSON.parse(chunk_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "pdf-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal 1, document.document_pages.count
    assert_equal 1, document.document_chunks.count
    assert_equal 1, document.document_embeddings.count
    assert document.document_pages.first.image.attached?

    user_content = payload.dig("messages", 1, "content")
    assert_kind_of Array, user_content

    text_content = user_content.select { |part| part.fetch("type") == "text" }.map { |part| part.fetch("text") }.join("\n")
    image_content = user_content.select { |part| part.fetch("type") == "image_url" }

    assert_includes text_content, "Embedded PDF page 1"
    assert_includes text_content, "OCR PDF page text"
    assert_equal 1, image_content.count
    assert_match %r{\Adata:image/png;base64,}, image_content.first.dig("image_url", "url")
    assert_equal "auto", image_content.first.dig("image_url", "detail")
  end

  test "chunks and embeds image-only PDFs with page screenshots" do
    ProcessDocumentJob.pdf_command_runner = FakeImageOnlyPdfCommandRunner.new
    document = create_pdf_document
    clear_enqueued_jobs

    ProcessDocumentJob.perform_now(document)

    document.reload
    chunk_request = chat_request_for("document_chunks")
    payload = JSON.parse(chunk_request.fetch(:payload))
    user_content = payload.dig("messages", 1, "content")

    assert_kind_of Array, user_content

    text_content = user_content.select { |part| part.fetch("type") == "text" }.map { |part| part.fetch("text") }.join("\n")
    image_content = user_content.select { |part| part.fetch("type") == "image_url" }

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal 1, document.document_chunks.count
    assert_equal 1, document.document_embeddings.count
    assert_includes text_content, "Return chunks whose content starts on the CURRENT page"
    assert_equal 1, image_content.count
    assert_match %r{\Adata:image/png;base64,}, image_content.first.dig("image_url", "url")
  end

  private

    def create_document
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Power of Attorney",
        category: :general,
        file: {
          io: StringIO.new("This is the uploaded test document."),
          filename: "power-of-attorney.txt",
          content_type: "text/plain"
        }
      )
    end

    def create_pdf_document
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "PDF Document",
        category: :educational,
        file: {
          io: StringIO.new("%PDF-1.4\n% fake test pdf"),
          filename: "document.pdf",
          content_type: "application/pdf"
        }
      )
    end

    def chat_request_for(schema_name)
      FakeConnection.requests.find do |request|
        next false unless request.fetch(:url).include?("/chat/completions")

        JSON.parse(request.fetch(:payload)).dig("response_format", "json_schema", "name") == schema_name
      end
    end
end
