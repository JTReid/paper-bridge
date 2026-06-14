require "base64"
require "test_helper"

class Documents::PreparePdfTest < ActiveSupport::TestCase
  ONE_BY_ONE_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  )

  class FakePdfCommandRunner
    attr_reader :calls

    def initialize(page_count: 2)
      @page_count = page_count
      @calls = []
    end

    def page_count(_pdf_path)
      calls << [ :page_count ]
      @page_count
    end

    def extract_text(_pdf_path, page_number:)
      calls << [ :extract_text, page_number ]
      "Embedded text for page #{page_number}"
    end

    def render_page(_pdf_path, page_number:, output_dir:, dpi:)
      calls << [ :render_page, page_number, dpi ]
      path = File.join(output_dir, "page-#{page_number}.png")
      File.binwrite(path, ONE_BY_ONE_PNG)
      path
    end

    def ocr_image(image_path)
      page_number = File.basename(image_path)[/\d+/].to_i
      calls << [ :ocr_image, page_number ]
      "OCR text for page #{page_number}"
    end
  end

  test "prepares every PDF page with embedded text, OCR text, and page images" do
    document = create_pdf_document
    command_runner = FakePdfCommandRunner.new
    clear_enqueued_jobs

    payload = Documents::PreparePdf.call(document, command_runner: command_runner)

    document.reload
    pages = document.document_pages.to_a

    assert_equal "prepared", document.preparation_status
    assert_equal "pdf-v1", document.prepared_payload.fetch("preparation_version")
    assert_equal 2, document.prepared_payload.fetch("page_count")
    assert_equal 225, document.prepared_payload.fetch("dpi")
    assert_equal 2, pages.count
    assert pages.all? { |page| page.status == "processed" }
    assert pages.all? { |page| page.image.attached? }
    assert_equal "Embedded text for page 1", pages.first.embedded_text
    assert_equal "OCR text for page 1", pages.first.ocr_text
    assert_includes payload.fetch(:full_text), "Embedded text for page 2"
    assert_includes payload.fetch(:full_text), "OCR text for page 2"
    assert_includes command_runner.calls, [ :render_page, 1, 225 ]
    assert_includes command_runner.calls, [ :render_page, 2, 225 ]
  end

  test "preparation is idempotent for existing page records" do
    document = create_pdf_document
    command_runner = FakePdfCommandRunner.new
    clear_enqueued_jobs

    Documents::PreparePdf.call(document, command_runner: command_runner)

    assert_no_difference -> { document.document_pages.count } do
      Documents::PreparePdf.call(document.reload, command_runner: command_runner)
    end
  end

  test "dispatcher routes PDFs to PDF preparation" do
    document = create_pdf_document
    command_runner = FakePdfCommandRunner.new(page_count: 1)
    clear_enqueued_jobs

    payload = Documents::Prepare.call(document, pdf_command_runner: command_runner)

    assert_equal "pdf", payload.fetch(:format)
    assert_equal 1, document.reload.document_pages.count
  end

  private

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
