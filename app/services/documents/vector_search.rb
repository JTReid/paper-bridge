# frozen_string_literal: true

module Documents
  class VectorSearch
    Result = Struct.new(:embedding, :chunk, :document, :page, :distance, :similarity, keyword_init: true)

    DEFAULT_LIMIT = 10

    def initialize(account:, query_embedding:, access_profile:, dependent: nil, limit: DEFAULT_LIMIT)
      @account = account
      @query_embedding = query_embedding
      @access_profile = access_profile
      @dependent = dependent
      @limit = limit.to_i.clamp(1, 50)
    end

    def call
      return [] if allowed_labels.empty?

      relation.map do |embedding|
        build_result(embedding)
      end
    end

    private

      attr_reader :account, :query_embedding, :access_profile, :dependent, :limit

      def relation
        scope = DocumentEmbedding
          .joins(document_chunk: :document)
          .where(document_chunks: { account_id: account.id, label: allowed_labels })
          .includes(document_chunk: [ :document, :document_page ])
          .nearest_neighbors(:embedding, query_embedding, distance: DocumentEmbedding::DISTANCE_METRIC)

        scope = scope.where(documents: { dependent_id: dependent.id }) if dependent
        scope.limit(limit)
      end

      def allowed_labels
        @allowed_labels ||= access_profile.allowed_chunk_labels
      end

      def build_result(embedding)
        chunk = embedding.document_chunk

        Result.new(
          embedding: embedding,
          chunk: chunk,
          document: chunk.document,
          page: chunk.document_page,
          distance: embedding.neighbor_distance.to_f,
          similarity: 1.0 - embedding.neighbor_distance.to_f
        )
      end
  end
end
