# frozen_string_literal: true

module Agentic
  class DocumentSearchPipeline < Pipeline
    def initialize(progress_tracker: nil, context: {}, connection: RestClient)
      super(
        [
          [ Agents::QueryEmbedder, { connection: connection }, { tag: :query_embedder } ],
          [ Agents::VectorRetriever, {}, { tag: :vector_retriever } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      query_embedding = results.find { |result| result.tag == :query_embedder }&.result || {}
      retrieval = results.find { |result| result.tag == :vector_retriever }&.result || {}

      {
        query_embedding: query_embedding,
        results: retrieval.fetch(:results, []),
        result_count: retrieval.fetch(:result_count, 0),
        allowed_chunk_labels: retrieval.fetch(:allowed_chunk_labels, [])
      }
    end
  end
end
