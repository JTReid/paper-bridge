# frozen_string_literal: true

require_relative "ai_definitions"

module Setup
  class AiConfigurationCheck
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
        definitions = AiDefinitions.agents
        agents = AgentType.includes(:llm, :prompts).where(name: definitions.keys).index_by(&:name)

        definitions.each do |name, definition|
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

          check_model(agent, definition.fetch(:operation))
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
        definitions = AiDefinitions.schemas
        records = JsonSchema.where(name: definitions.keys).index_by(&:name)

        definitions.each do |name, definition|
          record = records[name]
          unless record
            errors << "JsonSchema #{name} is missing; initialize this AI configuration schema."
            next
          end

          differences = difference_paths(functional_shape(definition), functional_shape(record.schema))
          next if differences.empty?

          paths = differences.first(6).join(", ")
          paths += ", and other fields" if differences.length > 6
          errors << "JsonSchema #{name} is incompatible at #{paths}; refresh its AI configuration schema."
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
