require "test_helper"

class UpdateDocumentMetadataSchemasTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_seed
  end

  test "updates only document metadata schemas and is repeatable" do
    target_names = %w[
      openai_document_summary anthropic_document_summary
      openai_image_document_extraction anthropic_image_document_extraction
    ]
    JsonSchema.where(name: target_names).update_all(schema: { old_schema: true })
    generic = JsonSchema.find_by!(name: "openai_structured_summary")
    generic.update!(schema: { custom_generic_schema: true })
    custom_model = Llm.create!(name: "custom-local-model", provider_class: "Agentic::Providers::Openai")
    agent = AgentType.find_by!(name: "document_summarizer")
    agent.update!(llm: custom_model)
    agent.prompts.active.first.update!(system_directive: "Keep this custom prompt.")

    other_schemas = JsonSchema.where.not(name: target_names).order(:id).map(&:attributes)
    model_settings = [ Llm, AgentType, Prompt ].map { |model| model.order(:id).map(&:attributes) }

    assert_no_difference -> { JsonSchema.count } do
      capture_io { load Rails.root.join("scripts/update_document_metadata_schemas.rb") }
    end

    {
      "document_summary" => Documents::MetadataSchemas.document_summary,
      "image_document_extraction" => Documents::MetadataSchemas.image_document_extraction
    }.each do |name, expected_schema|
      openai_schema = JsonSchema.find_by!(name: "openai_#{name}").schema
      anthropic_schema = JsonSchema.find_by!(name: "anthropic_#{name}").schema
      assert_equal expected_schema.deep_stringify_keys, openai_schema.dig("response_format", "json_schema", "schema")
      assert_equal true, openai_schema.dig("response_format", "json_schema", "strict")
      assert_equal expected_schema.deep_stringify_keys, anthropic_schema.fetch("tools").first.fetch("input_schema")
      assert_equal Document.categories.keys, expected_schema.dig(:properties, :category, :enum)
      assert_includes expected_schema[:required], "category"
      assert_includes expected_schema[:required], "description"
      assert_equal false, expected_schema[:additionalProperties]
    end

    assert_equal other_schemas, JsonSchema.where.not(name: target_names).order(:id).map(&:attributes)
    assert_equal model_settings, [ Llm, AgentType, Prompt ].map { |model| model.order(:id).map(&:attributes) }
    updated_schemas = JsonSchema.order(:id).map(&:attributes)

    capture_io { load Rails.root.join("scripts/update_document_metadata_schemas.rb") }

    assert_equal updated_schemas, JsonSchema.order(:id).map(&:attributes)
    assert_equal model_settings, [ Llm, AgentType, Prompt ].map { |model| model.order(:id).map(&:attributes) }
  end

  test "fails without writes if a required schema record is missing" do
    JsonSchema.find_by!(name: "anthropic_image_document_extraction").destroy!
    JsonSchema.find_by!(name: "openai_document_summary").update!(schema: { old_schema: true })
    before = JsonSchema.order(:id).map(&:attributes)

    assert_raises ActiveRecord::RecordNotFound do
      capture_io { load Rails.root.join("scripts/update_document_metadata_schemas.rb") }
    end

    assert_equal before, JsonSchema.order(:id).map(&:attributes)
  end
end
