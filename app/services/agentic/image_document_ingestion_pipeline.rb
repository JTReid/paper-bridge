# frozen_string_literal: true

module Agentic
  class ImageDocumentIngestionPipeline < Pipeline
    def initialize(progress_tracker: nil, context: {}, connection: RestClient)
      super(
        [
          [ Agents::ImageDocumentExtractor, { connection: connection }, { tag: :image_document_extractor } ],
          [ Agents::DocumentEmbedder, { connection: connection }, { tag: :document_embedder } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      {
        extraction: results.find { |result| result.tag == :image_document_extractor }&.result || {},
        embeddings: results.find { |result| result.tag == :document_embedder }&.result || {}
      }
    end
  end
end
