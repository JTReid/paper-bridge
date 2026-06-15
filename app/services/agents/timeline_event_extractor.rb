# frozen_string_literal: true

require "set"

module Agents
  class TimelineEventExtractor
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      call
      set_response
      response
    end

    def requirements
      {
        model: llm.name,
        system: prompt.system_directive,
        prompt: extraction_prompt,
        max_tokens: 4_000,
        response_format: "structured_json",
        schema_name: "timeline_events"
      }
    end

    def step_started
      "Extracting timeline events"
    end

    def step_complete
      "Timeline events extracted"
    end

    def setup_content
      @document = locate_document!
      @chunks = document.document_chunks.includes(:document_page).order(:chunk_index).to_a
      @content = evidence_text

      raise Agentic::Errors::ConfigurationError, "Document has no chunks for timeline extraction" if chunks.empty?
    end

    def agent_type_name
      "timeline_event_extractor"
    end

    def set_response
      parsed = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      created_events = persist_events(Array(parsed[:events]))

      @response = {
        timeline_event_count: created_events.count,
        timeline_event_ids: created_events.map(&:id)
      }

      log_activity(
        action: "timeline_events_extracted",
        message: "Timeline events extracted from document chunks",
        metadata: response
      )
    end

    private

      attr_reader :document, :chunks

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end

      def extraction_prompt
        <<~PROMPT
          Document title: #{document.title}
          Original filename: #{document.original_filename}

          Extract timeline events from the evidence chunks below.
          Each event must be sourced to exactly one document_chunk_id from the evidence.
          Include exact dates when present.
          Include age-derived dates when enough information is present. For example, if DOB is March 14, 2018 and a milestone happened at 24 months, use 2020-03-14 with date_source age_derived and date_precision age_derived.
          Include approximate ranges when the text says things like "around 18 to 24 months".
          Use empty strings for unknown date fields.
          Return only events that are useful in a child's care timeline.
          Use event_type values from this list: #{TimelineEvent::EVENT_TYPES.join(", ")}.
          Use date_precision values from this list: #{TimelineEvent::DATE_PRECISIONS.join(", ")}.
          Use date_source values from this list: #{TimelineEvent::DATE_SOURCES.join(", ")}.

          Evidence chunks:
          #{evidence_text}
        PROMPT
      end

      def evidence_text
        @evidence_text ||= chunks.map do |chunk|
          <<~EVIDENCE
            document_chunk_id: #{chunk.id}
            chunk_index: #{chunk.chunk_index}
            page_number: #{chunk.document_page.page_number}
            label: #{chunk.label}
            content:
            #{chunk.content}
          EVIDENCE
        end.join("\n")
      end

      def persist_events(events_data)
        TimelineEvent.transaction do
          TimelineEvent.where(document_chunk: chunks).destroy_all

          seen_hashes = Set.new
          events_data.filter_map do |event_data|
            create_event(event_data, seen_hashes)
          end
        end
      end

      def create_event(event_data, seen_hashes)
        chunk = chunk_by_id[event_data[:document_chunk_id].to_i]
        return if chunk.blank?

        attributes = event_attributes(chunk, event_data)
        return if attributes[:source_quote].blank?
        return if seen_hashes.include?([ chunk.id, attributes[:content_hash] ])

        seen_hashes << [ chunk.id, attributes[:content_hash] ]
        TimelineEvent.create!(attributes)
      end

      def event_attributes(chunk, event_data)
        event_type = normalized_value(event_data[:event_type], TimelineEvent::EVENT_TYPES, "observation")
        title = event_data[:title].to_s.squish.presence || event_type.humanize
        description = event_data[:description].to_s.squish.presence || title
        occurred_on = parse_date(event_data[:occurred_on])
        started_on = parse_date(event_data[:started_on])
        ended_on = parse_date(event_data[:ended_on])

        {
          document_chunk: chunk,
          event_type: event_type,
          title: title,
          description: description,
          occurred_on: occurred_on,
          started_on: started_on,
          ended_on: ended_on,
          date_precision: normalized_value(event_data[:date_precision], TimelineEvent::DATE_PRECISIONS, "unknown"),
          date_source: normalized_value(event_data[:date_source], TimelineEvent::DATE_SOURCES, "undated"),
          source_quote: event_data[:source_quote].to_s.squish,
          content_hash: TimelineEvent.content_hash_for(
            event_type: event_type,
            title: title,
            description: description,
            occurred_on: occurred_on,
            started_on: started_on,
            ended_on: ended_on
          ),
          metadata: {
            source: "timeline_event_extractor",
            page_number: chunk.document_page.page_number
          }
        }
      end

      def parse_date(value)
        value = value.to_s.strip
        return if value.blank?

        Date.iso8601(value)
      rescue Date::Error
        nil
      end

      def normalized_value(value, allowed_values, fallback)
        value = value.to_s
        return value if allowed_values.include?(value)

        fallback
      end

      def chunk_by_id
        @chunk_by_id ||= chunks.index_by(&:id)
      end
  end
end
