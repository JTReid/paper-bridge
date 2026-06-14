# frozen_string_literal: true

module Agentic
  class ExamplePipeline < Pipeline
    def initialize(progress_tracker: nil, context: {})
      super(
        [
          [ Agents::StructuredTextSummarizer, {}, { tag: :summarizer } ],
          [ Agents::StructuredTextValidator, {}, { tag: :validator } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      results.find { |result| result.tag == :summarizer }&.result
    end
  end
end
