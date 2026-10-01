# frozen_string_literal: true

require_relative "ai_definitions"
require_relative "ai_configuration_check"

module Setup
  # Syncs AI configuration to AiDefinitions on every release: creates missing
  # records and updates any that differ, so the definitions are the single
  # source of truth for every app. Records the definitions don't name are left
  # alone.
  module AiConfiguration
    def self.call
      AgentType.transaction do
        models = AiDefinitions.models.to_h do |name, provider|
          model = Llm.find_or_initialize_by(name: name)
          model.update!(provider_class: provider)
          [ name, model ]
        end

        AiDefinitions.agents.each do |name, definition|
          agent = AgentType.find_or_initialize_by(name: name)
          agent.update!(llm: models.fetch(definition.fetch(:model)))
          sync_prompt(agent, definition.fetch(:prompt))
        end

        AiDefinitions.schemas.each do |name, schema|
          JsonSchema.find_or_initialize_by(name: name).update!(schema: schema)
        end

        errors = AiConfigurationCheck.call
        raise Agentic::Errors::ConfigurationError, errors.join("\n") if errors.any?
      end
    end

    # Leaves exactly one active prompt with the defined text. A changed prompt
    # becomes a new active version; earlier versions stay as inactive history.
    def self.sync_prompt(agent, directive)
      active = agent.prompts.active.to_a
      return if active.one? && active.first.system_directive == directive

      agent.prompts.active.update_all(is_active: false, updated_at: Time.current)
      agent.prompts.create!(system_directive: directive, is_active: true)
    end
    private_class_method :sync_prompt
  end
end
