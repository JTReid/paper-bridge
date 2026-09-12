# frozen_string_literal: true

module Documents
  class PipelineConfigurationCheck
    AGENT_OPERATIONS = {
      "document_chunker" => :chat,
      "document_summarizer" => :chat,
      "document_embedder" => :embeddings,
      "image_document_extractor" => :chat,
      "timeline_event_extractor" => :chat,
      "query_embedder" => :embeddings
    }.freeze
    SCHEMA_ANNOTATIONS = %w[$comment title description examples default].freeze

    def self.call
      new.call
    end

    def call
      @errors = []
      check_agents
      check_embedding_dimensions
      check_schemas
      errors
    end

    private

      attr_reader :errors

      def check_agents
        agents = AgentType.includes(:llm, :prompts).where(name: AGENT_OPERATIONS.keys).index_by(&:name)

        AGENT_OPERATIONS.each do |name, operation|
          agent = agents[name]
          unless agent
            errors << "AgentType #{name} is missing; initialize its model and active prompt."
            next
          end

          active_prompts = agent.prompts.select(&:is_active?)
          if active_prompts.length != 1
            errors << "AgentType #{name} must have exactly one active prompt."
          elsif active_prompts.first.system_directive.blank?
            errors << "AgentType #{name} has a blank active prompt."
          end

          check_model(agent, operation)
        end
      end

      def check_model(agent, operation)
        model = agent.llm
        unless model&.name.present?
          errors << "AgentType #{agent.name} must have a model with a nonblank name."
          return
        end

        provider = model.provider_klass
        unless provider.is_a?(Class) && provider.respond_to?(:default_operation_type) &&
            %i[call parse_response].all? { |method| provider.instance_methods.include?(method) } &&
            provider.const_defined?(:ENDPOINTS) && provider.const_get(:ENDPOINTS).is_a?(Hash) &&
            provider.const_get(:ENDPOINTS).key?(operation)
          errors << "AgentType #{agent.name} provider must support the #{operation} operation."
        end

        if operation == :embeddings && (provider != Agentic::Providers::Openai || model.name != DocumentEmbedding::MODEL)
          errors << "AgentType #{agent.name} must use OpenAI #{DocumentEmbedding::MODEL} to match stored document embeddings."
        end
      rescue NameError, TypeError
        errors << "AgentType #{agent.name} has an unresolvable provider class."
      end

      def check_embedding_dimensions
        column = DocumentEmbedding.columns_hash["embedding"]
        unless column && column.limit == DocumentEmbedding::DIMENSIONS
          errors << "DocumentEmbedding.embedding must store #{DocumentEmbedding::DIMENSIONS} dimensions; check the database schema."
        end
      end

      def check_schemas
        definitions = {
          "document_chunks" => PipelineSchemas.document_chunks,
          "document_summary" => MetadataSchemas.document_summary,
          "image_document_extraction" => MetadataSchemas.image_document_extraction,
          "timeline_events" => PipelineSchemas.timeline_events
        }
        names = definitions.keys.flat_map { |name| [ "openai_#{name}", "anthropic_#{name}" ] }
        records = JsonSchema.where(name: names).index_by(&:name)

        definitions.each do |name, definition|
          %w[openai anthropic].each do |provider|
            record_name = "#{provider}_#{name}"
            record = records[record_name]
            unless record
              errors << "JsonSchema #{record_name} is missing; initialize this document pipeline schema."
              next
            end

            expected = functional_shape(wrapped_schema(provider, name, definition))
            differences = difference_paths(expected, functional_shape(record.schema))
            next if differences.empty?

            paths = differences.first(6).join(", ")
            paths += ", and other fields" if differences.length > 6
            errors << "JsonSchema #{record_name} is incompatible at #{paths}; refresh its document pipeline schema."
          end
        end
      end

      def wrapped_schema(provider, name, definition)
        if provider == "openai"
          {
            response_format: {
              type: "json_schema",
              json_schema: { name: name, strict: true, schema: definition }
            }
          }
        else
          {
            tools: [ { name: name, input_schema: definition } ],
            tool_choice: { type: "tool", name: name }
          }
        end
      end

      def functional_shape(value, properties: false)
        case value
        when Hash
          value.each_with_object({}) do |(key, child), shape|
            key = key.to_s
            next if !properties && SCHEMA_ANNOTATIONS.include?(key)

            shape[key] = functional_shape(child, properties: !properties && key == "properties")
            shape[key] = shape[key].sort_by(&:to_s) if !properties && %w[required enum].include?(key) && shape[key].is_a?(Array)
          end
        when Array
          value.map { |child| functional_shape(child) }
        else
          value
        end
      end

      def difference_paths(expected, actual, path = "$")
        return [] if expected == actual
        return [ path ] unless expected.is_a?(Hash) && actual.is_a?(Hash)

        (expected.keys | actual.keys).flat_map do |key|
          child_path = "#{path}.#{key}"
          if !expected.key?(key) || !actual.key?(key)
            [ child_path ]
          else
            difference_paths(expected[key], actual[key], child_path)
          end
        end
      end
  end
end
