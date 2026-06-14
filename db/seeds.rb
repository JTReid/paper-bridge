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

[
  [
    "structured_text_summarizer",
    "Summarize the user's text as structured JSON. Return only fields allowed by the configured schema."
  ],
  [
    "structured_text_validator",
    "Validate the structured JSON. Approve only if it is parseable, source-grounded, and contains no unsupported fields."
  ],
  [
    "document_summarizer",
    "Summarize uploaded PaperBridge documents as grounded structured JSON. Return only fields allowed by the configured schema."
  ]
].each do |name, directive|
  agent_type = AgentType.find_or_create_by!(name: name) do |record|
    record.llm = openai
  end
  agent_type.update!(llm: openai)

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

document_summary_schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string" },
    summary: { type: "string" },
    key_points: {
      type: "array",
      items: { type: "string" }
    },
    document_type: { type: "string" },
    notable_dates: {
      type: "array",
      items: { type: "string" }
    }
  },
  required: %w[title summary key_points document_type notable_dates]
}

{
  "structured_summary" => summary_schema,
  "structured_validation" => validation_schema,
  "document_summary" => document_summary_schema
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
