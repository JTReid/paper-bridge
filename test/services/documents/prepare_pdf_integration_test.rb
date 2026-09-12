require "test_helper"
require "vips"

class Documents::PreparePdfIntegrationTest < ActiveSupport::TestCase
  test "prepares a real ten-page PDF with embedded text OCR and valid page images" do
    original = Rails.root.join("test/fixtures/files/multipage_school_record.pdf").binread
    document = Document.create!(
      account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
      title: "Synthetic school record", category: :educational,
      file: { io: StringIO.new(original), filename: "school-record.pdf", content_type: "application/pdf" }
    )
    clear_enqueued_jobs

    # Exercise the installed pdfinfo, pdftotext, pdftoppm and tesseract tools.
    # Missing tools fail this check; no document job or AI provider is run.
    payload = Documents::Prepare.call(document)

    document.reload
    assert_predicate document, :prepared?
    assert_nil document.preparation_error
    assert_equal 10, payload.fetch(:page_count)
    assert_equal (1..10).to_a, document.document_pages.pluck(:page_number)
    assert_equal original, document.file.download
    assert_empty document.pipeline_runs

    [ document.document_pages.first, document.document_pages.last ].each do |page|
      marker = format("School record page %02d", page.page_number)
      assert_predicate page, :processed?
      assert_includes page.embedded_text, marker
      assert_match(/School record page 0?#{page.page_number}\b/i, page.ocr_text)
      assert_includes document.prepared_payload.fetch("full_text"), marker
      assert_equal "image/png", page.image.blob.content_type
      image = Vips::Image.new_from_buffer(page.image.download, "")
      assert_equal [ 1500, 750 ], [ image.width, image.height ]
    end
  end
end
