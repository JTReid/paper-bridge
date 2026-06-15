# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
openai = Llm.find_or_create_by!(name: "gpt-5.4-nano") do |llm|
  llm.provider_class = "Agentic::Providers::Openai"
end
openai.update!(provider_class: "Agentic::Providers::Openai")

openai_mini = Llm.find_or_create_by!(name: "gpt-5.4-mini") do |llm|
  llm.provider_class = "Agentic::Providers::Openai"
end
openai_mini.update!(provider_class: "Agentic::Providers::Openai")

openai_embeddings = Llm.find_or_create_by!(name: "text-embedding-3-large") do |llm|
  llm.provider_class = "Agentic::Providers::Openai"
end
openai_embeddings.update!(provider_class: "Agentic::Providers::Openai")

[
  [
    "structured_text_summarizer",
    openai,
    "Summarize the user's text as structured JSON. Return only fields allowed by the configured schema."
  ],
  [
    "structured_text_validator",
    openai,
    "Validate the structured JSON. Approve only if it is parseable, source-grounded, and contains no unsupported fields."
  ],
  [
    "document_chunker",
    openai,
    "Create coherent, page-aware search chunks from prepared PaperBridge document pages. Use adjacent-page context for continuity, keep headings with their bodies, label each chunk with the configured taxonomy, and return only fields allowed by the configured schema."
  ],
  [
    "document_embedder",
    openai_embeddings,
    "Embed PaperBridge document chunks for vector search indexing."
  ],
  [
    "query_embedder",
    openai_embeddings,
    "Embed user search queries for account-scoped PaperBridge vector retrieval."
  ],
  [
    "search_answer_generator",
    openai_mini,
    "Answer PaperBridge search questions using only the retrieved evidence chunks. Cite supporting chunks for material claims and state limitations when evidence is incomplete."
  ],
  [
    "timeline_event_extractor",
    openai_mini,
    "Extract source-grounded care timeline events from PaperBridge document chunks. Preserve dates, derive dates from age plus date of birth only when supported by evidence, and cite the source chunk for every event."
  ]
].each do |name, llm, directive|
  agent_type = AgentType.find_or_create_by!(name: name) do |record|
    record.llm = llm
  end
  agent_type.update!(llm: llm)

  prompt = agent_type.prompts.active.first_or_initialize
  prompt.system_directive = directive
  prompt.is_active = true
  prompt.save!
end

summary_schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    key_points: {
      type: "array",
      items: { type: "string" }
    }
  },
  required: %w[title summary key_points]
}

validation_schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    status: { type: "string", enum: %w[APPROVED REJECTED] },
    reasons: {
      type: "array",
      items: { type: "string" }
    }
  },
  required: %w[status reasons]
}

document_chunks_schema = {
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
            enum: %w[
              medical
              education
              therapy
              behavior
              legal
              financial
              general
            ]
          }
        },
        required: %w[content label]
      }
    }
  },
  required: %w[chunks]
}

search_answer_schema = {
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
          chunk_id: { type: "integer" },
          document_title: { type: "string" },
          page_number: { type: "integer" },
          quote: { type: "string" }
        },
        required: %w[chunk_id document_title page_number quote]
      }
    },
    limitations: {
      type: "array",
      items: { type: "string" }
    }
  },
  required: %w[answer citations limitations]
}

timeline_events_schema = {
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

{
  "structured_summary" => summary_schema,
  "structured_validation" => validation_schema,
  "document_chunks" => document_chunks_schema,
  "search_answer" => search_answer_schema,
  "timeline_events" => timeline_events_schema
}.each do |name, schema|
  openai_schema = JsonSchema.find_or_initialize_by(name: "openai_#{name}")
  openai_schema.schema = {
    response_format: {
      type: "json_schema",
      json_schema: {
        name: name,
        strict: true,
        schema: schema
      }
    }
  }
  openai_schema.save!

  anthropic_schema = JsonSchema.find_or_initialize_by(name: "anthropic_#{name}")
  anthropic_schema.schema = {
    tools: [
      {
        name: name,
        description: "Return #{name.tr("_", " ")} as structured JSON.",
        input_schema: schema
      }
    ],
    tool_choice: {
      type: "tool",
      name: name
    }
  }
  anthropic_schema.save!
end
