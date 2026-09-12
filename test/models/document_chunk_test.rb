require "test_helper"

class DocumentChunkTest < ActiveSupport::TestCase
  test "normalizes content for display and stricter hash identity" do
    content = "  Speech   Therapy:\r\n60 minutes weekly.\n\n\n"

    assert_equal "Speech   Therapy:\n60 minutes weekly.", DocumentChunk.normalize_content(content)
    assert_equal(
      Digest::SHA256.hexdigest("speech therapy: 60 minutes weekly."),
      DocumentChunk.content_hash_for(content)
    )
  end

  test "requires a known label" do
    chunk = build_chunk
    assert_predicate chunk, :valid?

    chunk.label = "random"
    assert_not chunk.valid?
    assert_includes chunk.errors[:label], "is not included in the list"
  end

  test "requires the page to belong to the chunk's document within the same account" do
    other_document = Document.create!(
      account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
      file: { io: StringIO.new("Another planning document."), filename: "another-plan.txt", content_type: "text/plain" }
    )
    other_page = other_document.document_pages.create!(account: accounts(:greenfield), page_number: 1)
    chunk = build_chunk
    assert_predicate chunk, :valid?

    chunk.document_page = other_page

    assert_not chunk.valid?
    assert_equal [ :document_page ], chunk.errors.attribute_names
    assert_includes chunk.errors[:document_page], "must belong to the document"
  end

  test "requires the account to match the document" do
    chunk = build_chunk
    assert_predicate chunk, :valid?

    chunk.account = accounts(:other)

    assert_not chunk.valid?
    assert_equal [ :account ], chunk.errors.attribute_names
    assert_includes chunk.errors[:account], "must match the document"
  end

  private

    def build_chunk
      DocumentChunk.new(
        account: accounts(:greenfield),
        document: documents(:advance_directive),
        document_page: document_pages(:advance_directive_first),
        content: "Legal planning content",
        content_hash: DocumentChunk.content_hash_for("Legal planning content"),
        label: "legal",
        chunk_index: 99
      )
    end
end
