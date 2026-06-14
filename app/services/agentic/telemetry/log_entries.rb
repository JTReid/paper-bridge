# frozen_string_literal: true

module Agentic
  module Telemetry
    module LogEntries
      private

      def log_entries
        Array(pipeline_run.pipeline_log&.entries)
      end

      def log_entries_for(event_type)
        log_entries.select { |entry| entry["event_type"] == event_type }
      end
    end
  end
end
