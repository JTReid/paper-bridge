require "test_helper"

class Documents::PipelineConfigurationTest < ActiveSupport::TestCase
  SUMMARY_SCHEMA_NAMES = %w[openai_document_summary anthropic_document_summary].freeze
  IMAGE_SCHEMA_NAMES = %w[openai_image_document_extraction anthropic_image_document_extraction].freeze

  setup do
    Rails.application.load_seed
  end

  test "repairs legacy document configuration without resetting custom models or unrelated records" do
    make_summary_schemas_legacy
    remove_image_configuration
    custom_model = Llm.create!(name: "gpt-5.6-luna", provider_class: "Agentic::Providers::Openai")
    search_agent = AgentType.find_by!(name: "search_answer_generator")
    search_agent.update!(llm: custom_model)
    search_agent.prompts.active.first.update!(system_directive: "Keep this customized search answer prompt.")
    before = configuration_snapshot
    expected_updates = JsonSchema.where(name: SUMMARY_SCHEMA_NAMES).map { |record| [ "JsonSchema", record.id ] }

    travel 1.minute do
      Documents::PipelineConfiguration.sync!
    end

    after = configuration_snapshot
    assert_empty before.keys - after.keys
    changed_existing = before.keys.select { |key| before.fetch(key) != after.fetch(key) }
    assert_equal expected_updates.sort, changed_existing.sort
    assert_equal({ "JsonSchema" => 2, "AgentType" => 1, "Prompt" => 1 }, (after.keys - before.keys).map(&:first).tally)
    assert_metadata_schemas_current
    assert_empty Documents::PipelineConfigurationCheck.call
    assert_equal custom_model, search_agent.reload.llm
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    assert_equal "gpt-5.4-mini", image_agent.llm.name
    assert_equal "Agentic::Providers::Openai", image_agent.llm.provider_class
    assert_equal 1, image_agent.prompts.active.count
    assert_predicate image_agent.prompts.active.first.system_directive, :present?

    travel 2.minutes do
      Documents::PipelineConfiguration.sync!
    end

    assert_equal after, configuration_snapshot, "A repeated sync must leave every row and timestamp unchanged"
  end

  test "preserves an existing custom image model and prompts without requiring the fallback model" do
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    image_agent.llm.update!(name: "gpt-5.6-luna")
    image_agent.prompts.active.first.update!(system_directive: "Keep my custom image extraction instructions.")
    image_agent.prompts.create!(system_directive: "Archived image instructions.", is_active: false)
    make_summary_schemas_legacy
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    before_models_and_prompts = configuration_snapshot.reject { |(model, _id), _attributes| model == "JsonSchema" }

    Documents::PipelineConfiguration.sync!

    assert_empty Documents::PipelineConfigurationCheck.call
    assert_metadata_schemas_current
    assert_equal before_models_and_prompts,
      configuration_snapshot.reject { |(model, _id), _attributes| model == "JsonSchema" }
    assert_not Llm.exists?(name: "gpt-5.4-mini")
  end

  test "adds a missing active image prompt while preserving the existing agent and inactive prompts" do
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    image_agent.prompts.active.update_all(is_active: false)
    before = configuration_snapshot

    assert_difference "Prompt.count", 1 do
      Documents::PipelineConfiguration.sync!
    end

    after = configuration_snapshot
    before.each { |key, attributes| assert_equal attributes, after.fetch(key) }
    assert_equal [ "Prompt" ], (after.keys - before.keys).map(&:first)
    assert_equal 1, image_agent.prompts.active.count
    assert_empty Documents::PipelineConfigurationCheck.call
  end

  test "a missing fallback model rolls back schema repairs and creates no replacement configuration" do
    make_summary_schemas_legacy
    remove_image_configuration
    Llm.find_by!(name: "gpt-5.4-mini").update!(name: "gpt-5.6-luna")
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Documents::PipelineConfiguration.sync!
    end

    assert_includes error.message, "gpt-5.4-mini"
    assert_equal before, configuration_snapshot
  end

  test "an incompatible embedding configuration rolls back every proposed repair" do
    make_summary_schemas_legacy
    remove_image_configuration
    AgentType.find_by!(name: "document_embedder").update!(llm: Llm.find_by!(name: "gpt-5.4-mini"))
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Documents::PipelineConfiguration.sync!
    end

    assert_includes error.message, "document_embedder"
    assert_equal before, configuration_snapshot
  end

  test "does not overwrite a blank existing image prompt to make the checker pass" do
    make_summary_schemas_legacy
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    AgentType.find_by!(name: "image_document_extractor").prompts.active.first.update_columns(system_directive: "   ")
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Documents::PipelineConfiguration.sync!
    end

    assert_includes error.message, "image_document_extractor"
    assert_equal before, configuration_snapshot
  end

  test "does not silently choose between duplicate active image prompts" do
    make_summary_schemas_legacy
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    AgentType.find_by!(name: "image_document_extractor").prompts.create!(
      system_directive: "A second active image prompt.", is_active: true
    )
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Documents::PipelineConfiguration.sync!
    end

    assert_includes error.message, "image_document_extractor"
    assert_equal before, configuration_snapshot
  end

  private

    def make_summary_schemas_legacy
      SUMMARY_SCHEMA_NAMES.each do |name|
        record = JsonSchema.find_by!(name: name)
        schema = record.schema.deep_dup
        object_schema = if name.start_with?("openai_")
          schema.dig("response_format", "json_schema", "schema")
        else
          schema.fetch("tools").first.fetch("input_schema")
        end
        object_schema.fetch("properties").except!("category", "description")
        object_schema.fetch("required").reject! { |key| key.in?(%w[category description]) }
        record.update!(schema: schema)
      end
    end

    def remove_image_configuration
      image_agent = AgentType.find_by!(name: "image_document_extractor")
      image_agent.prompts.destroy_all
      image_agent.destroy!
      JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    end

    def configuration_snapshot
      [ Llm, AgentType, Prompt, JsonSchema ].flat_map do |model|
        model.order(:id).map { |record| [ [ model.name, record.id ], record.attributes ] }
      end.to_h
    end

    def assert_metadata_schemas_current
      {
        "document_summary" => Documents::MetadataSchemas.document_summary,
        "image_document_extraction" => Documents::MetadataSchemas.image_document_extraction
      }.each do |name, schema|
        assert_equal schema.deep_stringify_keys,
          JsonSchema.find_by!(name: "openai_#{name}").schema.dig("response_format", "json_schema", "schema")
        assert_equal schema.deep_stringify_keys,
          JsonSchema.find_by!(name: "anthropic_#{name}").schema.fetch("tools").first.fetch("input_schema")
      end
    end
end
