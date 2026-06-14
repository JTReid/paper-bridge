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

  test "validates label taxonomy and document page ownership" do
    chunk = DocumentChunk.new(
      account: accounts(:greenfield),
      document: documents(:advance_directive),
      document_page: document_pages(:advance_directive_first),
      content: "Legal planning content",
      content_hash: DocumentChunk.content_hash_for("Legal planning content"),
      label: "legal",
      chunk_index: 99
    )

    assert_predicate chunk, :valid?

    chunk.label = "random"
    assert_not chunk.valid?
    assert_includes chunk.errors[:label], "is not included in the list"
  end
end
