require "base64"
require "test_helper"

class ProcessDocumentJobTest < ActiveJob::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  class FakeConnection
    class << self
      attr_accessor :last_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.last_request = kwargs
        {
          choices: [
            {
              message: {
                content: {
                  title: "Durable Power of Attorney",
                  summary: "This document names an agent and describes authority.",
                  key_points: [
                    "Names an agent",
                    "Describes delegated authority"
                  ],
                  document_type: "legal",
                  notable_dates: []
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
    ProcessDocumentJob.llm_connection = FakeConnection
  end

  teardown do
    ProcessDocumentJob.llm_connection = @original_connection
    ProcessDocumentJob.pdf_command_runner = @original_pdf_command_runner
  end

  test "prepares the file, runs the pipeline, and persists the summary" do
    document = create_document
    clear_enqueued_jobs

    assert_difference -> { PipelineRun.count } do
      ProcessDocumentJob.perform_now(document)
    end

    document.reload
    pipeline_run = document.pipeline_runs.last
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "text-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal "Durable Power of Attorney", document.summary.fetch("title")
    assert_equal "This document names an agent and describes authority.", document.summary.fetch("summary")
    assert_equal "completed", pipeline_run.state
    assert_equal "gpt-5.4-nano", payload.fetch("model")
    assert_includes payload.dig("messages", 1, "content"), "This is the uploaded test document."
    assert pipeline_run.pipeline_log.entries.any? { |entry| entry["event_type"] == "llm_call" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "document_summarized" }
  end

  test "prepares PDFs before summarizing them" do
    ProcessDocumentJob.pdf_command_runner = FakePdfCommandRunner.new
    document = create_pdf_document
    clear_enqueued_jobs

    ProcessDocumentJob.perform_now(document)

    document.reload
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "pdf-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal 1, document.document_pages.count
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

  test "summarizes image-only PDFs with page screenshots" do
    ProcessDocumentJob.pdf_command_runner = FakeImageOnlyPdfCommandRunner.new
    document = create_pdf_document
    clear_enqueued_jobs

    ProcessDocumentJob.perform_now(document)

    document.reload
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))
    user_content = payload.dig("messages", 1, "content")

    assert_kind_of Array, user_content

    text_content = user_content.select { |part| part.fetch("type") == "text" }.map { |part| part.fetch("text") }.join("\n")
    image_content = user_content.select { |part| part.fetch("type") == "image_url" }

    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_includes text_content, "Use both the extracted text and the screenshots"
    assert_equal 1, image_content.count
    assert_match %r{\Adata:image/png;base64,}, image_content.first.dig("image_url", "url")
  end

  private

    def create_document
      Document.create!(
        account: accounts(:greenfield),
        user: users(:family_admin),
        title: "Power of Attorney",
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
        user: users(:family_admin),
        title: "PDF Document",
        file: {
          io: StringIO.new("%PDF-1.4\n% fake test pdf"),
          filename: "document.pdf",
          content_type: "application/pdf"
        }
      )
    end
end
