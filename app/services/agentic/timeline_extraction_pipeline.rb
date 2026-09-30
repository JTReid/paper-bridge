# frozen_string_literal: true

module Agentic
  class TimelineExtractionPipeline < Pipeline
    def initialize(progress_tracker: nil, context: {}, connection: RestClient)
      super(
        [
          [ Agents::TimelineEventExtractor, { connection: connection }, { tag: :timeline_event_extractor } ]
        ],
        progress_tracker: progress_tracker,
        context: context
      )
    end

    def to_response
      results.find { |result| result.tag == :timeline_event_extractor }&.result || {}
    end
  end
end
