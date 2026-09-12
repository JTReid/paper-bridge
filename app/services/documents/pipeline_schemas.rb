# frozen_string_literal: true

module Documents
  module PipelineSchemas
    def self.document_chunks
      {
        type: "object",
        additionalProperties: false,
        properties: {
          chunks: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                content: { type: "string" },
                label: {
                  type: "string",
                  enum: DocumentChunk::LABELS
                }
              },
              required: %w[content label]
            }
          }
        },
        required: %w[chunks]
      }
    end

    def self.timeline_events
      {
        type: "object",
        additionalProperties: false,
        properties: {
          events: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                document_chunk_id: { type: "integer" },
                event_type: {
                  type: "string",
                  enum: TimelineEvent::EVENT_TYPES
                },
                title: { type: "string" },
                description: { type: "string" },
                occurred_on: { type: "string" },
                started_on: { type: "string" },
                ended_on: { type: "string" },
                date_precision: {
                  type: "string",
                  enum: TimelineEvent::DATE_PRECISIONS
                },
                date_source: {
                  type: "string",
                  enum: TimelineEvent::DATE_SOURCES
                },
                source_quote: { type: "string" }
              },
              required: %w[
                document_chunk_id
                event_type
                title
                description
                occurred_on
                started_on
                ended_on
                date_precision
                date_source
                source_quote
              ]
            }
          }
        },
        required: %w[events]
      }
    end
  end
end
