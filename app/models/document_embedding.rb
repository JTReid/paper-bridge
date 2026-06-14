class DocumentEmbedding < ApplicationRecord
  PROVIDER = "openai"
  MODEL = "text-embedding-3-large"
  DIMENSIONS = 3_072
  DISTANCE_METRIC = "cosine"

  belongs_to :document_chunk

  has_neighbors :embedding, dimensions: DIMENSIONS

  validates :provider, :model, :dimensions, :distance_metric, :embedding, presence: true
  validates :document_chunk_id, uniqueness: { scope: %i[provider model] }
end
