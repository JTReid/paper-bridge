# frozen_string_literal: true

module Agentic
  class DocumentSummaryPipeline < Pipeline
    def initialize(progress_tracker: nil, context: {}, connection: RestClient)
      super(
        [
          [ Agents::DocumentSummarizer, { connection: connection }, { tag: :document_summarizer } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      results.find { |result| result.tag == :document_summarizer }&.result || {}
    end
  end
end
