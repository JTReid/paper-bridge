require "test_helper"

class DocumentEmbeddingTest < ActiveSupport::TestCase
  test "stores model identity with the vector" do
    embedding = DocumentEmbedding.new(
      document_chunk: document_chunks(:one),
      provider: DocumentEmbedding::PROVIDER,
      model: DocumentEmbedding::MODEL,
      dimensions: DocumentEmbedding::DIMENSIONS,
      distance_metric: DocumentEmbedding::DISTANCE_METRIC,
      embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001)
    )

    assert_predicate embedding, :valid?
  end
end
