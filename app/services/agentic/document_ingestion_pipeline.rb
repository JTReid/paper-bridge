# frozen_string_literal: true

module Agentic
  class DocumentIngestionPipeline < Pipeline
    def initialize(progress_tracker: nil, context: {}, connection: RestClient)
      super(
        [
          [ Agents::DocumentChunker, { connection: connection }, { tag: :document_chunker } ],
          [ Agents::DocumentEmbedder, { connection: connection }, { tag: :document_embedder } ],
          [ Agents::TimelineEventExtractor, { connection: connection }, { tag: :timeline_event_extractor } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      {
        chunks: results.find { |result| result.tag == :document_chunker }&.result || {},
        embeddings: results.find { |result| result.tag == :document_embedder }&.result || {},
        timeline_events: results.find { |result| result.tag == :timeline_event_extractor }&.result || {}
      }
    end
  end
end
