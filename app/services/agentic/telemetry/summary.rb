# frozen_string_literal: true

module Agentic
  module Telemetry
    class Summary
      def initialize(pipeline_run, by_agent: false)
        @pipeline_run = pipeline_run
        @by_agent = by_agent
      end

      def call
        summaries.reduce({}) { |summary, telemetry| summary.merge(telemetry.call) }
      end

      private

      attr_reader :pipeline_run, :by_agent

      def summaries
        [
          PricingSummary.new(pipeline_run, by_agent: by_agent),
          ElapsedTimeSummary.new(pipeline_run, by_agent: by_agent)
        ]
      end
    end
  end
end
