# frozen_string_literal: true

module Setup
  module AiDefinitions
    def self.models
      {
        "gpt-5.4-nano" => "Agentic::Providers::Openai",
        "gpt-5.4-mini" => "Agentic::Providers::Openai",
        "text-embedding-3-large" => "Agentic::Providers::Openai"
      }
    end

    def self.agents
      {
        "structured_text_summarizer" => {
          model: "gpt-5.4-nano", operation: :chat,
          prompt: "Summarize the user's text as structured JSON. Return only fields allowed by the configured schema."
        },
        "structured_text_validator" => {
          model: "gpt-5.4-nano", operation: :chat,
          prompt: "Validate the structured JSON. Approve only if it is parseable, source-grounded, and contains no unsupported fields."
        },
        "document_chunker" => {
          model: "gpt-5.4-nano", operation: :chat,
          prompt: "Create coherent, page-aware search chunks from prepared PaperBridge document pages. Use adjacent-page context for continuity, keep headings with their bodies, label each chunk with the configured taxonomy, and return only fields allowed by the configured schema."
        },
        "document_summarizer" => {
          model: "gpt-5.4-mini", operation: :chat,
          prompt: "Create concise, source-grounded summaries for parents and caregivers. Use plain language, explain necessary terms briefly, include only supported facts, and never mention internal processing mechanics. Return only fields allowed by the configured schema."
        },
        "document_embedder" => {
          model: "text-embedding-3-large", operation: :embeddings,
          prompt: "Embed PaperBridge document chunks for vector search indexing."
        },
        "image_document_extractor" => {
          model: "gpt-5.4-mini", operation: :chat,
          prompt: "Read uploaded image documents using vision, including printed and handwritten text. Preserve uncertainty instead of guessing, classify the document, summarize only visible evidence, and create useful search chunks. Return only fields allowed by the configured schema."
        },
        "query_embedder" => {
          model: "text-embedding-3-large", operation: :embeddings,
          prompt: "Embed user search queries for account-scoped PaperBridge vector retrieval."
        },
        "search_answer_generator" => {
          model: "gpt-5.4-mini", operation: :chat,
          prompt: "Answer questions for parents and caregivers using only their available records. Use plain language, cite the supporting sources for material claims, state what may be missing, and never mention internal processing mechanics."
        },
        "timeline_event_extractor" => {
          model: "gpt-5.4-mini", operation: :chat,
          prompt: "Extract source-grounded care timeline events from PaperBridge document chunks. Preserve dates, derive dates from age plus date of birth only when supported by evidence, and cite the source chunk for every event."
        }
      }
    end

    def self.schemas
      {
        "structured_summary" => structured_summary,
        "document_summary" => document_summary,
        "structured_validation" => structured_validation,
        "document_chunks" => document_chunks,
        "image_document_extraction" => image_document_extraction,
        "search_answer" => search_answer,
        "timeline_events" => timeline_events
      }.each_with_object({}) do |(name, schema), definitions|
        definitions["openai_#{name}"] = {
          response_format: {
            type: "json_schema",
            json_schema: { name: name, strict: true, schema: schema }
          }
        }
        definitions["anthropic_#{name}"] = {
          tools: [
            {
              name: name,
              description: "Return #{name.tr("_", " ")} as structured JSON.",
              input_schema: schema
            }
          ],
          tool_choice: { type: "tool", name: name }
        }
      end
    end

    def self.structured_summary
      {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string" },
          summary: { type: "string" },
          key_points: { type: "array", items: { type: "string" } }
        },
        required: %w[title summary key_points]
      }
    end
    private_class_method :structured_summary

    def self.structured_validation
      {
        type: "object",
        additionalProperties: false,
        properties: {
          status: { type: "string", enum: %w[APPROVED REJECTED] },
          reasons: { type: "array", items: { type: "string" } }
        },
        required: %w[status reasons]
      }
    end
    private_class_method :structured_validation

    def self.document_summary
      {
        type: "object",
        additionalProperties: false,
        properties: {
          title: { type: "string" },
          category: category,
          description: description,
          summary: { type: "string" },
          key_points: { type: "array", items: { type: "string" } }
        },
        required: %w[title category description summary key_points]
      }
    end
    private_class_method :document_summary

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
                label: { type: "string", enum: DocumentChunk::LABELS }
              },
              required: %w[content label]
            }
          }
        },
        required: %w[chunks]
      }
    end
    private_class_method :document_chunks

    def self.image_document_extraction
      {
        type: "object",
        additionalProperties: false,
        properties: {
          extracted_text: { type: "string", minLength: 1 },
          category: category,
          description: description,
          summary: { type: "string", minLength: 1 },
          key_points: { type: "array", items: { type: "string" } },
          search_chunks: {
            type: "array",
            minItems: 1,
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                content: { type: "string", minLength: 1 },
                label: { type: "string", enum: DocumentChunk::LABELS }
              },
              required: %w[content label]
            }
          }
        },
        required: %w[extracted_text category description summary key_points search_chunks]
      }
    end
    private_class_method :image_document_extraction

    def self.search_answer
      {
        type: "object",
        additionalProperties: false,
        properties: {
          answer: { type: "string" },
          citations: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                chunk_id: {
                  type: "integer",
                  description: "The temporary source number from the current prompt, not a database record ID."
                },
                document_title: { type: "string" },
                page_number: { type: "integer" },
                quote: { type: "string" }
              },
              required: %w[chunk_id document_title page_number quote]
            }
          },
          limitations: { type: "array", items: { type: "string" } }
        },
        required: %w[answer citations limitations]
      }
    end
    private_class_method :search_answer

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
                event_type: { type: "string", enum: TimelineEvent::EVENT_TYPES },
                title: { type: "string" },
                description: { type: "string" },
                occurred_on: { type: "string" },
                started_on: { type: "string" },
                ended_on: { type: "string" },
                date_precision: { type: "string", enum: TimelineEvent::DATE_PRECISIONS },
                date_source: { type: "string", enum: TimelineEvent::DATE_SOURCES },
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
    private_class_method :timeline_events

    def self.category
      { type: "string", enum: Document.categories.keys }
    end
    private_class_method :category

    def self.description
      {
        type: "string",
        minLength: 1,
        description: "One or two short source-grounded sentences identifying the document and its main purpose, separate from the fuller summary."
      }
    end
    private_class_method :description
  end
end
