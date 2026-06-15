require "test_helper"

class Documents::VectorSearchTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:greenfield)
    @document = documents(:advance_directive)
    @page = document_pages(:advance_directive_first)
    @owner_profile = Documents::SearchAccessProfile.new(role: "family_admin")
  end

  test "returns nearest chunks first" do
    far_chunk = create_chunk!("School accommodation", label: "education", chunk_index: 2)
    near_chunk = create_chunk!("Medical diagnosis", label: "medical", chunk_index: 3)

    create_embedding!(far_chunk, unit_vector(1))
    create_embedding!(near_chunk, unit_vector(0))

    results = search(query_embedding: unit_vector(0))

    assert_equal [ near_chunk, far_chunk ], results.map(&:chunk)
    assert_operator results.first.similarity, :>, results.second.similarity
  end

  test "filters by access profile labels before ranking" do
    medical_chunk = create_chunk!("Medical diagnosis", label: "medical", chunk_index: 2)
    education_chunk = create_chunk!("Classroom accommodation", label: "education", chunk_index: 3)

    create_embedding!(medical_chunk, unit_vector(0))
    create_embedding!(education_chunk, unit_vector(1))

    results = search(
      query_embedding: unit_vector(0),
      access_profile: Documents::SearchAccessProfile.new(role: "teacher")
    )

    assert_equal [ education_chunk ], results.map(&:chunk)
  end

  test "filters by account before ranking" do
    other_page = DocumentPage.create!(
      account: accounts(:other),
      document: documents(:outside_account),
      page_number: 1,
      embedded_text: "Other account page",
      ocr_text: "",
      status: "processed"
    )
    other_chunk = create_chunk!(
      "Other account medical match",
      account: accounts(:other),
      document: documents(:outside_account),
      page: other_page,
      label: "medical",
      chunk_index: 1
    )
    account_chunk = create_chunk!("Same account weaker match", label: "medical", chunk_index: 2)

    create_embedding!(other_chunk, unit_vector(0))
    create_embedding!(account_chunk, unit_vector(1))

    results = search(query_embedding: unit_vector(0))

    assert_equal [ account_chunk ], results.map(&:chunk)
  end

  test "returns an empty result set when no embeddings are indexed" do
    assert_empty search(query_embedding: unit_vector(0))
  end

  private

    def search(query_embedding:, access_profile: @owner_profile)
      Documents::VectorSearch.new(
        account: @account,
        query_embedding: query_embedding,
        access_profile: access_profile
      ).call
    end

    def create_chunk!(content, account: @account, document: @document, page: @page, label:, chunk_index:)
      normalized = DocumentChunk.normalize_content(content)

      DocumentChunk.create!(
        account: account,
        document: document,
        document_page: page,
        content: normalized,
        content_hash: DocumentChunk.content_hash_for(normalized),
        label: label,
        chunk_index: chunk_index
      )
    end

    def create_embedding!(chunk, embedding)
      chunk.document_embeddings.create!(
        provider: DocumentEmbedding::PROVIDER,
        model: DocumentEmbedding::MODEL,
        dimensions: DocumentEmbedding::DIMENSIONS,
        distance_metric: DocumentEmbedding::DISTANCE_METRIC,
        embedding: embedding
      )
    end

    def unit_vector(index)
      Array.new(DocumentEmbedding::DIMENSIONS, 0.0).tap do |vector|
        vector[index] = 1.0
      end
    end
end
