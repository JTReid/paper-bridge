require "test_helper"
require Rails.root.join("lib/setup/ai_configuration").to_s
require Rails.root.join("lib/setup/ai_configuration_check").to_s

class Setup::AiConfigurationCheckTest < ActiveSupport::TestCase
  setup do
    Prompt.delete_all
    AgentType.delete_all
    Llm.delete_all
    JsonSchema.delete_all
    Setup::AiConfiguration.call
  end

  test "checks current configuration without seeding writing jobs or provider calls" do
    custom_model = Llm.create!(name: "custom-answer-model", provider_class: "Agentic::Providers::Openai")
    AgentType.find_by!(name: "search_answer_generator").update!(llm: custom_model)
    before = configuration_snapshot

    assert_no_enqueued_jobs do
      with_stubbed_singleton_method(Rails.application, :load_seed, -> { flunk "The checker must not seed" }) do
        with_stubbed_singleton_method(Agentic::Providers::Openai, :new, ->(*) { flunk "The checker must not instantiate providers" }) do
          with_stubbed_singleton_method(Agentic::Providers::Anthropic, :new, ->(*) { flunk "The checker must not instantiate providers" }) do
            assert_empty Setup::AiConfigurationCheck.call
          end
        end
      end
    end

    assert_equal before, configuration_snapshot
    assert_equal custom_model, AgentType.find_by!(name: "search_answer_generator").llm
  end

  test "reports the deployed old summary and missing image configuration without repairing it" do
    JsonSchema.where(name: %w[openai_document_summary anthropic_document_summary]).find_each do |record|
      schema = record.schema.deep_dup
      definition = if record.name.start_with?("openai_")
        schema.dig("response_format", "json_schema", "schema")
      else
        schema.fetch("tools").first.fetch("input_schema")
      end
      definition.fetch("properties").except!("category", "description")
      definition.fetch("required").reject! { |field| %w[category description].include?(field) }
      record.update!(schema: schema)
    end
    JsonSchema.where(name: %w[openai_image_document_extraction anthropic_image_document_extraction]).destroy_all
    image_agent = AgentType.find_by!(name: "image_document_extractor")
    image_agent.prompts.destroy_all
    image_agent.destroy!
    before = configuration_snapshot

    errors = Setup::AiConfigurationCheck.call

    assert_equal 5, errors.length
    assert errors.any? { |error| error.include?("AgentType image_document_extractor is missing") }
    assert errors.any? { |error| error.include?("openai_document_summary is incompatible") && error.include?("category") }
    assert errors.any? { |error| error.include?("anthropic_document_summary is incompatible") }
    assert errors.any? { |error| error.include?("openai_image_document_extraction is missing") }
    assert errors.any? { |error| error.include?("anthropic_image_document_extraction is missing") }
    assert_equal before, configuration_snapshot
  end

  test "requires one nonblank active prompt per agent" do
    agent = AgentType.find_by!(name: "document_summarizer")
    prompt = agent.prompts.active.first
    prompt.update!(is_active: false)
    assert_includes Setup::AiConfigurationCheck.call, "AgentType document_summarizer must have exactly one active prompt."

    prompt.update!(is_active: true)
    duplicate = agent.prompts.create!(system_directive: "Another active directive", is_active: true)
    assert_includes Setup::AiConfigurationCheck.call, "AgentType document_summarizer must have exactly one active prompt."

    duplicate.destroy!
    prompt.update_column(:system_directive, "  ")
    assert_includes Setup::AiConfigurationCheck.call, "AgentType document_summarizer has a blank active prompt."
  end

  test "reports unresolvable providers and unsupported operations without printing stored values" do
    agent = AgentType.find_by!(name: "document_embedder")
    invalid_model = Llm.create!(name: "private-model-detail", provider_class: "PrivateInvalidProvider")
    agent.update!(llm: invalid_model)

    errors = Setup::AiConfigurationCheck.call
    assert_includes errors, "AgentType document_embedder has an unresolvable provider class."
    assert_not_includes errors.join, "PrivateInvalidProvider"
    assert_not_includes errors.join, "private-model-detail"

    invalid_model.update!(provider_class: "Agentic::Providers::Anthropic")
    errors = Setup::AiConfigurationCheck.call
    assert_includes errors, "AgentType document_embedder provider must support the embeddings operation."
    assert errors.any? { |error| error.include?("document_embedder must use OpenAI #{DocumentEmbedding::MODEL}") }
  end

  test "requires document and query embedding models to match the stored embedding contract" do
    wrong_model = Llm.create!(name: "different-embedding-model", provider_class: "Agentic::Providers::Openai")
    AgentType.where(name: %w[document_embedder query_embedder]).update_all(llm_id: wrong_model.id)

    errors = Setup::AiConfigurationCheck.call

    %w[document_embedder query_embedder].each do |name|
      assert_includes errors, "AgentType #{name} must use OpenAI #{DocumentEmbedding::MODEL} to match stored document embeddings."
    end
  end

  test "checks database embedding dimensions without changing the column" do
    wrong_column = Struct.new(:limit).new(1536)
    columns = DocumentEmbedding.columns_hash.merge("embedding" => wrong_column)

    with_stubbed_singleton_method(DocumentEmbedding, :columns_hash, columns) do
      assert_includes Setup::AiConfigurationCheck.call,
        "DocumentEmbedding.embedding must store #{DocumentEmbedding::DIMENSIONS} dimensions; check the database schema."
    end
  end

  test "allows descriptive annotations and schema key required and enum ordering changes" do
    record = JsonSchema.find_by!(name: "openai_document_summary")
    schema = record.schema.deep_dup
    definition = schema.dig("response_format", "json_schema", "schema")
    definition["description"] = "An alternate schema explanation."
    definition["title"] = "A display title."
    definition["$comment"] = "No behavioral difference."
    definition.fetch("required").reverse!
    definition["properties"] = definition.fetch("properties").to_a.reverse.to_h
    definition.fetch("properties").fetch("category").fetch("enum").reverse!
    definition.fetch("properties").fetch("description")["description"] = "Another annotation."
    record.update!(schema: schema)

    assert_empty Setup::AiConfigurationCheck.call
  end

  test "validates meaningful description and title properties rather than ignoring their names" do
    record = JsonSchema.find_by!(name: "openai_document_summary")
    schema = record.schema.deep_dup
    properties = schema.dig("response_format", "json_schema", "schema", "properties")
    properties.fetch("description")["type"] = "integer"
    properties.fetch("title")["type"] = "array"
    record.update!(schema: schema)

    error = Setup::AiConfigurationCheck.call.find { |entry| entry.include?(record.name) }

    assert_includes error, "properties.description.type"
    assert_includes error, "properties.title.type"
  end

  test "detects changed category chunk label and timeline enum contracts" do
    changes = {
      "openai_document_summary" => %w[properties category enum],
      "openai_document_chunks" => %w[properties chunks items properties label enum],
      "openai_timeline_events" => %w[properties events items properties event_type enum]
    }
    changes.each do |name, path|
      record = JsonSchema.find_by!(name: name)
      schema = record.schema.deep_dup
      schema.dig("response_format", "json_schema", "schema", *path) << "unsupported-value"
      record.update!(schema: schema)
    end

    errors = Setup::AiConfigurationCheck.call

    changes.each do |name, path|
      error = errors.find { |entry| entry.include?(name) }
      assert_includes error, path.join(".")
    end
    assert_not_includes errors.join, "unsupported-value"
  end

  test "requires strict OpenAI and selected Anthropic tool wrappers" do
    openai_record = JsonSchema.find_by!(name: "openai_document_summary")
    schema = openai_record.schema.deep_dup
    schema.fetch("response_format").fetch("json_schema")["strict"] = false
    openai_record.update!(schema: schema)
    anthropic_record = JsonSchema.find_by!(name: "anthropic_document_summary")
    schema = anthropic_record.schema.deep_dup
    schema.fetch("tool_choice")["name"] = "wrong_tool"
    anthropic_record.update!(schema: schema)

    errors = Setup::AiConfigurationCheck.call

    assert errors.any? { |error| error.include?(openai_record.name) && error.include?("json_schema.strict") }
    assert errors.any? { |error| error.include?(anthropic_record.name) && error.include?("tool_choice.name") }
  end

  test "reports all nine missing agents and fourteen missing schemas without creating them" do
    Prompt.delete_all
    AgentType.delete_all
    Llm.delete_all
    JsonSchema.delete_all
    before = configuration_snapshot

    errors = Setup::AiConfigurationCheck.call

    assert_equal 23, errors.length
    assert_equal 9, errors.count { |error| error.start_with?("AgentType ") && error.include?("is missing") }
    assert_equal 14, errors.count { |error| error.start_with?("JsonSchema ") && error.include?("is missing") }
    assert_equal before, configuration_snapshot
  end

  test "checks structured text and search answer configuration as well as documents" do
    validator = AgentType.find_by!(name: "structured_text_validator")
    validator.prompts.destroy_all
    validator.destroy!
    AgentType.find_by!(name: "structured_text_summarizer").prompts.active.first.update_column(:system_directive, "  ")
    AgentType.find_by!(name: "search_answer_generator").prompts.create!(system_directive: "Duplicate active answer prompt.", is_active: true)
    JsonSchema.find_by!(name: "anthropic_search_answer").destroy!
    answer_schema = JsonSchema.find_by!(name: "openai_search_answer")
    schema = answer_schema.schema.deep_dup
    schema.dig("response_format", "json_schema", "schema", "properties", "citations", "items", "properties", "chunk_id")["type"] = "string"
    answer_schema.update!(schema: schema)
    before = configuration_snapshot

    errors = Setup::AiConfigurationCheck.call

    assert_equal 5, errors.length
    assert errors.any? { |error| error.include?("AgentType structured_text_validator is missing") }
    assert_includes errors, "AgentType structured_text_summarizer has a blank active prompt."
    assert_includes errors, "AgentType search_answer_generator must have exactly one active prompt."
    assert errors.any? { |error| error.include?("anthropic_search_answer is missing") }
    assert errors.any? { |error| error.include?("openai_search_answer is incompatible") && error.include?("citations.items.properties.chunk_id.type") }
    assert_equal before, configuration_snapshot
  end

  test "checks both providers structured summary and validation schemas" do
    schema_names = %w[openai_structured_summary anthropic_structured_summary openai_structured_validation anthropic_structured_validation]
    JsonSchema.where(name: schema_names).destroy_all

    errors = Setup::AiConfigurationCheck.call

    assert_equal 4, errors.length
    schema_names.each do |name|
      assert errors.any? { |error| error.include?("JsonSchema #{name} is missing") }
    end
  end

  private

    def configuration_snapshot
      [ Llm, AgentType, Prompt, JsonSchema ].map { |model| model.order(:id).map(&:attributes) }
    end
end
