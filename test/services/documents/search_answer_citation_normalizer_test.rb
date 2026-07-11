require "test_helper"

class Documents::SearchAnswerCitationNormalizerTest < ActiveSupport::TestCase
  test "replaces ephemeral source references with canonical deduplicated sources" do
    document = documents(:advance_directive)
    page = document_pages(:advance_directive_first)
    first_chunk = document_chunks(:one)
    second_chunk = document.document_chunks.create!(
      account: document.account,
      document_page: page,
      content: "Additional source text from the same page.",
      content_hash: DocumentChunk.content_hash_for("Additional source text from the same page."),
      label: :general,
      chunk_index: 2
    )
    response = {
      answer: "The record supports this conclusion [1, 2]. Ignore this reference [99].",
      citations: [
        { chunk_id: 1, document_title: "Invented title", page_number: 99, quote: "Invented quote" },
        { chunk_id: 2, document_title: "Another title", page_number: 42, quote: "Another quote" },
        { chunk_id: 99, document_title: "Outside result", page_number: 1, quote: "No" }
      ],
      limitations: []
    }

    normalized = normalize(response, results: [ result_for(first_chunk), result_for(second_chunk) ])

    assert_equal "The record supports this conclusion [1]. Ignore this reference.", normalized[:answer]
    assert_equal 1, normalized[:citations].size
    assert_equal(
      {
        source_number: 1,
        document_id: document.id,
        document_title: document.title,
        page_number: page.page_number,
        quote: first_chunk.content
      },
      normalized[:citations].first
    )
    assert_not_includes normalized.to_s, "Invented"
    assert_not normalized[:citations].first.key?(:chunk_id)
  end

  test "numbers distinct document pages in first-reference order" do
    document = documents(:advance_directive)
    first_chunk = document_chunks(:one)
    second_page = document.document_pages.create!(
      account: document.account,
      page_number: 2,
      embedded_text: "Second page",
      ocr_text: "",
      status: :processed
    )
    second_chunk = document.document_chunks.create!(
      account: document.account,
      document_page: second_page,
      content: "Second-page source text.",
      content_hash: DocumentChunk.content_hash_for("Second-page source text."),
      label: :general,
      chunk_index: 2
    )
    response = {
      answer: "The later detail appears first [2], followed by earlier context [1].",
      citations: [],
      limitations: []
    }

    normalized = normalize(response, results: [ result_for(first_chunk), result_for(second_chunk) ])

    assert_equal "The later detail appears first [1], followed by earlier context [2].", normalized[:answer]
    assert_equal [ 2, 1 ], normalized[:citations].pluck(:page_number)
    assert_equal [ 1, 2 ], normalized[:citations].pluck(:source_number)
  end

  test "rejects mismatched result relationships and cleans the removed marker spacing" do
    chunk = document_chunks(:one)
    mismatched_result = Documents::VectorSearch::Result.new(
      chunk: chunk,
      document: documents(:outside_account),
      page: chunk.document_page,
      similarity: 0.9
    )

    normalized = normalize(
      { answer: "Unsafe [1] source.", citations: [ { chunk_id: 1 } ], limitations: [] },
      results: [ mismatched_result ]
    )

    assert_equal "Unsafe source.", normalized[:answer]
    assert_empty normalized[:citations]
  end

  private

    def normalize(response, results:)
      Documents::SearchAnswerCitationNormalizer.new(response: response, search_results: results).call
    end

    def result_for(chunk)
      Documents::VectorSearch::Result.new(
        chunk: chunk,
        document: chunk.document,
        page: chunk.document_page,
        similarity: 0.9
      )
    end
end
