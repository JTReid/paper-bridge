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

  test "preserves text beyond the former byte cutoff including a multibyte character at the boundary" do
    content = "x" * 199_999 + "é\n" + "Final observations and recommendations.\n" * 100
    document = create_text_document(content: content)

    payload = Documents::PrepareText.call(document)

    assert_equal content, payload.fetch(:full_text)
    assert_equal content, document.reload.prepared_payload.fetch("full_text")
    assert_equal content, document.document_pages.first.embedded_text
    assert_equal content.b, document.file.download
  end

  test "preserves UTF-8 characters and whitespace in binary attachment downloads" do
    content = "  Café — 東京 💙\n\tKeep this indentation.\n"
    document = create_text_document(content: content)

    payload = Documents::PrepareText.call(document)

    assert_equal content, payload.fetch(:full_text)
    assert_equal content, document.reload.document_pages.first.embedded_text
    assert_equal content.b, document.file.download
  end

  test "marks invalid UTF-8 bytes without dropping the surrounding text" do
    document = create_text_document(content: "Before \xFF after\n".b)

    payload = Documents::PrepareText.call(document)

    assert_equal "Before \uFFFD after\n", payload.fetch(:full_text)
    assert_predicate payload.fetch(:full_text), :valid_encoding?
    assert_equal "Before \xFF after\n".b, document.file.download
  end

  private

    def create_text_document(content: "This text should be summarized.")
      Document.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        title: "Text Document",
        category: :general,
        file: {
          io: StringIO.new(content),
          filename: "text-document.txt",
          content_type: "text/plain"
        }
      )
    end
end
