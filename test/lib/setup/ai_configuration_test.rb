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

    assert_equal %w[gpt-6-luna text-embedding-3-large], Llm.order(:name).pluck(:name)
    assert_equal [ "Agentic::Providers::Openai" ], Llm.distinct.pluck(:provider_class)
    assert_equal 9, AgentType.count
    assert_equal 9, Prompt.count
    assert_equal 14, JsonSchema.count
    {
      "gpt-6-luna" => %w[
        structured_text_summarizer structured_text_validator document_chunker document_summarizer
        image_document_extractor search_answer_generator timeline_event_extractor
      ],
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

  test "repairs legacy document schemas and missing image setup and resets customized search settings" do
    make_summary_schemas_legacy
    remove_agent("image_document_extractor")
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    custom_model = Llm.create!(name: "gpt-5.6-luna", provider_class: "Agentic::Providers::Openai")
    search_agent = AgentType.find_by!(name: "search_answer_generator")
    search_agent.update!(llm: custom_model)
    custom_prompt = search_agent.prompts.active.first
    custom_prompt.update!(system_directive: "Customized search answer prompt.")
    before = configuration_snapshot
    expected_updates = JsonSchema.where(name: SUMMARY_SCHEMA_NAMES).map { |record| [ "JsonSchema", record.id ] } +
      [ [ "AgentType", search_agent.id ], [ "Prompt", custom_prompt.id ] ]

    travel 1.minute do
      Setup::AiConfiguration.call
    end

    after = configuration_snapshot
    assert_empty before.keys - after.keys
    changed_existing = before.keys.select { |key| before.fetch(key) != after.fetch(key) }
    assert_equal expected_updates.sort, changed_existing.sort
    assert_equal({ "JsonSchema" => 2, "AgentType" => 1, "Prompt" => 2 }, (after.keys - before.keys).map(&:first).tally)
    assert_current_schemas
    assert_empty Setup::AiConfigurationCheck.call
    assert_equal "gpt-6-luna", search_agent.reload.llm.name
    assert_defined_prompt search_agent
    assert_not custom_prompt.reload.is_active?
  end

  test "syncs changed providers, agent models, and prompts while keeping prompt history and undefined records" do
    Llm.find_by!(name: "gpt-6-luna").update!(provider_class: "Agentic::Providers::Anthropic")
    custom_model = Llm.create!(name: "custom-image-model", provider_class: "Agentic::Providers::Anthropic")
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    image_agent.update!(llm: custom_model)
    image_agent.prompts.active.first.update!(system_directive: "Custom image extraction instructions.")
    image_agent.prompts.create!(system_directive: "Archived image instructions.", is_active: false)
    custom_schema = JsonSchema.create!(name: "unrelated_custom_schema", schema: { type: "object" })
    before = configuration_snapshot

    Setup::AiConfiguration.call

    assert_empty before.keys - configuration_snapshot.keys
    assert_equal "Agentic::Providers::Openai", Llm.find_by!(name: "gpt-6-luna").provider_class
    assert_equal "gpt-6-luna", image_agent.reload.llm.name
    assert_defined_prompt image_agent
    assert_equal [ "Archived image instructions.", "Custom image extraction instructions." ],
      image_agent.prompts.where(is_active: false).order(:system_directive).pluck(:system_directive)
    assert_equal before.fetch([ "Llm", custom_model.id ]), custom_model.reload.attributes
    assert_equal before.fetch([ "JsonSchema", custom_schema.id ]), custom_schema.reload.attributes
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "a changed definition moves agents to the new model and replaces the prompt on the next setup" do
    models = Setup::AiDefinitions.models.merge("gpt-next" => "Agentic::Providers::Openai")
    agents = Setup::AiDefinitions.agents.transform_values do |definition|
      definition.fetch(:model) == "gpt-6-luna" ? definition.merge(model: "gpt-next") : definition
    end
    agents["timeline_event_extractor"] = agents.fetch("timeline_event_extractor").merge(prompt: "Updated timeline instructions.")
    old_prompt = AgentType.find_by!(name: "timeline_event_extractor").prompts.active.sole

    with_stubbed_singleton_method(Setup::AiDefinitions, :models, models) do
      with_stubbed_singleton_method(Setup::AiDefinitions, :agents, agents) do
        Setup::AiConfiguration.call
      end
    end

    assert_equal 7, agents.count { |_name, definition| definition.fetch(:model) == "gpt-next" }
    agents.each do |name, definition|
      assert_equal definition.fetch(:model), AgentType.find_by!(name: name).llm.name
    end
    timeline_agent = AgentType.find_by!(name: "timeline_event_extractor")
    assert_equal "Updated timeline instructions.", timeline_agent.prompts.active.sole.system_directive
    assert_not old_prompt.reload.is_active?
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
    assert_equal "gpt-6-luna", AgentType.find_by!(name: "search_answer_generator").llm.name
    assert_equal 1, validator.prompts.active.count
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "recreates a renamed default model and moves every agent back to it" do
    renamed_model = Llm.find_by!(name: "gpt-6-luna")
    renamed_model.update!(name: "custom-chat-model")
    remove_agent("search_answer_generator")
    before = configuration_snapshot

    Setup::AiConfiguration.call

    after = configuration_snapshot
    assert_equal({ "Llm" => 1, "AgentType" => 1, "Prompt" => 1 }, (after.keys - before.keys).map(&:first).tally)
    Setup::AiDefinitions.agents.each do |name, definition|
      assert_equal definition.fetch(:model), AgentType.find_by!(name: name).llm.name
    end
    assert_equal before.fetch([ "Llm", renamed_model.id ]), renamed_model.reload.attributes
    assert_not AgentType.exists?(llm: renamed_model)
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "an invalid definition fails setup and rolls back every change" do
    make_summary_schemas_legacy
    remove_agent("image_document_extractor")
    JsonSchema.where(name: IMAGE_SCHEMA_NAMES).destroy_all
    custom_model = Llm.create!(name: "custom-chat-model", provider_class: "Agentic::Providers::Openai")
    AgentType.find_by!(name: "search_answer_generator").update!(llm: custom_model)
    agents = Setup::AiDefinitions.agents.merge(
      "document_embedder" => Setup::AiDefinitions.agents.fetch("document_embedder").merge(model: "gpt-6-luna")
    )
    before = configuration_snapshot

    error = assert_raises Agentic::Errors::ConfigurationError do
      with_stubbed_singleton_method(Setup::AiDefinitions, :agents, agents) do
        Setup::AiConfiguration.call
      end
    end

    assert_includes error.message, "document_embedder"
    assert_equal before, configuration_snapshot
  end

  test "replaces blank or duplicate active prompts with the defined prompt" do
    search_agent = AgentType.find_by!(name: "search_answer_generator")
    search_agent.prompts.active.first.update_column(:system_directive, "   ")
    validator = AgentType.find_by!(name: "structured_text_validator")
    validator.prompts.create!(system_directive: "A second active validation prompt.", is_active: true)

    Setup::AiConfiguration.call

    assert_defined_prompt search_agent
    assert_defined_prompt validator
    assert_equal 2, validator.prompts.where(is_active: false).count
    assert_empty Setup::AiConfigurationCheck.call
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

    def assert_defined_prompt(agent)
      assert_equal Setup::AiDefinitions.agents.fetch(agent.name).fetch(:prompt), agent.prompts.active.sole.system_directive
    end

    def assert_current_schemas
      Setup::AiDefinitions.schemas.each do |name, schema|
        assert_equal schema.deep_stringify_keys, JsonSchema.find_by!(name: name).schema
      end
    end
end
