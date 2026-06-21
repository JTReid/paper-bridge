class DocumentEmbedding < ApplicationRecord
  PROVIDER = "openai"
  MODEL = "text-embedding-3-large"
  DIMENSIONS = 3_072
  DISTANCE_METRIC = "cosine"

  belongs_to :document_chunk

  has_neighbors :embedding, dimensions: DIMENSIONS

  after_create_commit :broadcast_document_processing_stats
  after_destroy_commit :broadcast_document_processing_stats

  validates :provider, :model, :dimensions, :distance_metric, :embedding, presence: true
  validates :document_chunk_id, uniqueness: { scope: %i[provider model] }

  private

    def broadcast_document_processing_stats
      document_chunk&.document&.broadcast_processing_stats_update
    end
end
