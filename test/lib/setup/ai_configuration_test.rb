require "test_helper"
require Rails.root.join("lib/setup/ai_configuration").to_s

class Setup::AiConfigurationTest < ActiveSupport::TestCase
  SUMMARY_SCHEMA_NAMES = %w[openai_document_summary anthropic_document_summary].freeze
  IMAGE_SCHEMA_NAMES = %w[openai_image_document_extraction anthropic_image_document_extraction].freeze

  setup do
    clear_configuration
    Setup::AiConfiguration.call
  end

  test "initializes all AI configuration from empty tables and repeated setup leaves timestamps unchanged" do
    clear_configuration

    assert_no_enqueued_jobs do
      with_stubbed_singleton_method(Agentic::Providers::Openai, :new, ->(*) { flunk "Setup must not instantiate providers" }) do
        with_stubbed_singleton_method(Agentic::Providers::Anthropic, :new, ->(*) { flunk "Setup must not instantiate providers" }) do
          Setup::AiConfiguration.call
        end
      end
    end

    assert_equal %w[gpt-5.4-mini gpt-5.4-nano text-embedding-3-large], Llm.order(:name).pluck(:name)
    assert_equal [ "Agentic::Providers::Openai" ], Llm.distinct.pluck(:provider_class)
    assert_equal 9, AgentType.count
    assert_equal 9, Prompt.count
    assert_equal 14, JsonSchema.count
    {
      "gpt-5.4-nano" => %w[structured_text_summarizer structured_text_validator document_chunker],
      "gpt-5.4-mini" => %w[document_summarizer image_document_extractor search_answer_generator timeline_event_extractor],
      "text-embedding-3-large" => %w[document_embedder query_embedder]
    }.each do |model_name, names|
      names.each do |name|
        agent = AgentType.find_by!(name: name)
        assert_equal model_name, agent.llm.name
        assert_equal 1, agent.prompts.active.count
        assert_predicate agent.prompts.active.first.system_directive, :present?
      end
    end
    schema_names = %w[structured_summary structured_validation document_summary document_chunks image_document_extraction search_answer timeline_events]
    assert_equal schema_names.flat_map { |name| [ "openai_#{name}", "anthropic_#{name}" ] }.sort,
      JsonSchema.order(:name).pluck(:name)
    assert_empty Setup::AiConfigurationCheck.call
    before = configuration_snapshot

    travel 1.minute do
      Setup::AiConfiguration.call
    end

    assert_equal before, configuration_snapshot, "A repeated setup must preserve all rows and timestamps"
  end

  test "repairs legacy document schemas and missing image setup without changing customized search settings" do
    make_summary_schemas_legacy
    remove_agent("image_document_extractor")
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    custom_model = Llm.create!(name: "gpt-5.6-luna", provider_class: "Agentic::Providers::Openai")
    search_agent = AgentType.find_by!(name: "search_answer_generator")
    search_agent.update!(llm: custom_model)
    search_agent.prompts.active.first.update!(system_directive: "Keep this customized search answer prompt.")
    before = configuration_snapshot
    expected_updates = JsonSchema.where(name: SUMMARY_SCHEMA_NAMES).map { |record| [ "JsonSchema", record.id ] }

    travel 1.minute do
      Setup::AiConfiguration.call
    end

    after = configuration_snapshot
    assert_empty before.keys - after.keys
    changed_existing = before.keys.select { |key| before.fetch(key) != after.fetch(key) }
    assert_equal expected_updates.sort, changed_existing.sort
    assert_equal({ "JsonSchema" => 2, "AgentType" => 1, "Prompt" => 1 }, (after.keys - before.keys).map(&:first).tally)
    assert_current_schemas
    assert_empty Setup::AiConfigurationCheck.call
    assert_equal custom_model, search_agent.reload.llm
  end

  test "preserves existing model providers bindings and active and inactive prompts" do
    Llm.find_by!(name: "gpt-5.4-nano").update!(provider_class: "Agentic::Providers::Anthropic")
    custom_model = Llm.create!(name: "custom-image-model", provider_class: "Agentic::Providers::Anthropic")
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    image_agent.update!(llm: custom_model)
    image_agent.prompts.active.first.update!(system_directive: "Keep my custom image extraction instructions.")
    image_agent.prompts.create!(system_directive: "Archived image instructions.", is_active: false)
    JsonSchema.create!(name: "unrelated_custom_schema", schema: { type: "object" })
    make_summary_schemas_legacy
    before = configuration_snapshot
    expected_updates = JsonSchema.where(name: SUMMARY_SCHEMA_NAMES).map { |record| [ "JsonSchema", record.id ] }

    travel 1.minute do
      Setup::AiConfiguration.call
    end

    after = configuration_snapshot
    assert_equal before.keys.sort, after.keys.sort
    assert_equal expected_updates.sort, before.keys.select { |key| before.fetch(key) != after.fetch(key) }.sort
    assert_equal custom_model, image_agent.reload.llm
    assert_current_schemas
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "repairs missing search and structured text configuration while preserving prompt history" do
    remove_agent("search_answer_generator")
    JsonSchema.where(name: %w[openai_search_answer anthropic_search_answer]).destroy_all
    validator = AgentType.find_by!(name: "structured_text_validator")
    validator.prompts.active.update_all(is_active: false)
    before = configuration_snapshot

    Setup::AiConfiguration.call

    after = configuration_snapshot
    before.each { |key, attributes| assert_equal attributes, after.fetch(key) }
    assert_equal({ "JsonSchema" => 2, "AgentType" => 1, "Prompt" => 2 }, (after.keys - before.keys).map(&:first).tally)
    assert_equal "gpt-5.4-mini", AgentType.find_by!(name: "search_answer_generator").llm.name
    assert_equal 1, validator.prompts.active.count
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "creates a missing default model without rebinding agents that use a renamed model" do
    renamed_model = Llm.find_by!(name: "gpt-5.4-mini")
    renamed_model.update!(name: "custom-chat-model")
    remove_agent("search_answer_generator")
    before = configuration_snapshot

    Setup::AiConfiguration.call

    after = configuration_snapshot
    before.each { |key, attributes| assert_equal attributes, after.fetch(key) }
    assert_equal({ "Llm" => 1, "AgentType" => 1, "Prompt" => 1 }, (after.keys - before.keys).map(&:first).tally)
    assert_equal "gpt-5.4-mini", AgentType.find_by!(name: "search_answer_generator").llm.name
    assert_equal renamed_model, AgentType.find_by!(name: "document_summarizer").llm
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "an incompatible embedding binding rolls back new models schemas agents and prompts" do
    make_summary_schemas_legacy
    remove_agent("image_document_extractor")
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    Llm.find_by!(name: "gpt-5.4-mini").update!(name: "custom-chat-model")
    AgentType.find_by!(name: "document_embedder").update!(llm: Llm.find_by!(name: "gpt-5.4-nano"))
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Setup::AiConfiguration.call
    end

    assert_includes error.message, "document_embedder"
    assert_equal before, configuration_snapshot
  end

  test "does not overwrite a blank existing search prompt to make setup succeed" do
    make_summary_schemas_legacy
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    AgentType.find_by!(name: "search_answer_generator").prompts.active.first.update_column(:system_directive, "   ")
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Setup::AiConfiguration.call
    end

    assert_includes error.message, "search_answer_generator"
    assert_equal before, configuration_snapshot
  end

  test "does not silently choose between duplicate active structured text prompts" do
    make_summary_schemas_legacy
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    AgentType.find_by!(name: "structured_text_validator").prompts.create!(
      system_directive: "A second active validation prompt.", is_active: true
    )
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      Setup::AiConfiguration.call
    end

    assert_includes error.message, "structured_text_validator"
    assert_equal before, configuration_snapshot
  end

  private

    def clear_configuration
      Prompt.delete_all
      AgentType.delete_all
      Llm.delete_all
      JsonSchema.delete_all
    end

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

    def remove_agent(name)
      agent = AgentType.find_by!(name: name)
      agent.prompts.destroy_all
      agent.destroy!
    end

    def configuration_snapshot
      [ Llm, AgentType, Prompt, JsonSchema ].flat_map do |model|
        model.order(:id).map { |record| [ [ model.name, record.id ], record.attributes ] }
      end.to_h
    end

    def assert_current_schemas
      Setup::AiDefinitions.schemas.each do |name, schema|
        assert_equal schema.deep_stringify_keys, JsonSchema.find_by!(name: name).schema
      end
    end
end
