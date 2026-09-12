require "test_helper"

class Agents::DocumentSummarizerTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed
  end

  test "includes complete evidence beyond 60000 characters and every later chunk in the summary request" do
    first_chunk = document_chunks(:one)
    first_content = "Beginning of the record.\n" + "Detailed observations and recommendations.\n" * 2_000
    first_chunk.update!(content: first_content, content_hash: DocumentChunk.content_hash_for(first_content))
    last_content = "Final page: the family requested communication supports — including an AAC evaluation."
    last_chunk = first_chunk.document.document_chunks.create!(
      account: first_chunk.account, document_page: first_chunk.document_page,
      content: last_content, content_hash: DocumentChunk.content_hash_for(last_content),
      label: "education", chunk_index: 2
    )
    agent = Agents::DocumentSummarizer.new(context: { document_gid: first_chunk.document.to_global_id.to_s })

    request = agent.requirements

    assert_operator first_content.length, :>, 60_000
    assert_includes request.fetch(:prompt), first_content
    assert_includes request.fetch(:prompt), last_content
    assert_includes request.fetch(:prompt), "document_chunk_id: #{first_chunk.id}"
    assert_includes request.fetch(:prompt), "document_chunk_id: #{last_chunk.id}"
    assert_operator request.fetch(:prompt).index(first_content), :<, request.fetch(:prompt).index(last_content)
    assert_not_includes request.fetch(:prompt), "Only the first"
  end
end
