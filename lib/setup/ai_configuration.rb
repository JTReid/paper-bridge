# frozen_string_literal: true

require_relative "ai_definitions"
require_relative "ai_configuration_check"

module Setup
  module AiConfiguration
    def self.call
      AgentType.transaction do
        models = AiDefinitions.models.to_h do |name, provider|
          model = Llm.find_or_create_by!(name: name) { |record| record.provider_class = provider }
          [ name, model ]
        end

        AiDefinitions.agents.each do |name, definition|
          agent = AgentType.find_or_create_by!(name: name) do |record|
            record.llm = models.fetch(definition.fetch(:model))
          end
          unless agent.prompts.active.exists?
            agent.prompts.create!(system_directive: definition.fetch(:prompt), is_active: true)
          end
        end

        AiDefinitions.schemas.each do |name, schema|
          JsonSchema.find_or_initialize_by(name: name).update!(schema: schema)
        end

        errors = AiConfigurationCheck.call
        raise Agentic::Errors::ConfigurationError, errors.join("\n") if errors.any?
      end
    end
  end
end
