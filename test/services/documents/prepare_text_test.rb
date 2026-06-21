require "test_helper"

class Documents::PrepareTextTest < ActiveSupport::TestCase
  test "prepares text documents into a document-level payload and first page" do
    document = create_text_document
    clear_enqueued_jobs

    payload = Documents::PrepareText.call(document)

    document.reload
    assert_equal "prepared", document.preparation_status
    assert_equal "text-v1", payload.fetch(:preparation_version)
    assert_equal "This text should be summarized.", document.prepared_payload.fetch("full_text")
    assert_equal 1, document.document_pages.count
    assert_equal "This text should be summarized.", document.document_pages.first.embedded_text
    assert_equal "", document.document_pages.first.ocr_text
    assert_equal 1, document.prepared_payload.fetch("pages").count
    assert_not_nil document.prepared_at
  end

  private

    def create_text_document
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Text Document",
        category: :general,
        file: {
          io: StringIO.new("This text should be summarized."),
          filename: "text-document.txt",
          content_type: "text/plain"
        }
      )
    end
end
