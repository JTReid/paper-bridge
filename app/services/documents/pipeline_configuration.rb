# frozen_string_literal: true

module Documents
  module PipelineConfiguration
    IMAGE_AGENT_NAME = "image_document_extractor"
    IMAGE_MODEL_NAME = "gpt-5.4-mini"
    IMAGE_PROMPT = "Read uploaded image documents using vision, including printed and handwritten text. Preserve uncertainty instead of guessing, classify the document, summarize only visible evidence, and create useful search chunks. Return only fields allowed by the configured schema."

    def self.sync!
      AgentType.transaction do
        MetadataSchemas.update!
        agent = AgentType.find_or_initialize_by(name: IMAGE_AGENT_NAME)
        if agent.new_record?
          agent.llm = Llm.find_by(name: IMAGE_MODEL_NAME, provider_class: "Agentic::Providers::Openai")
          unless agent.llm
            raise Agentic::Errors::ConfigurationError, "Cannot initialize #{IMAGE_AGENT_NAME}: existing OpenAI Llm #{IMAGE_MODEL_NAME} is missing"
          end
          agent.save!
        end

        unless agent.prompts.active.exists?
          agent.prompts.create!(system_directive: IMAGE_PROMPT, is_active: true)
        end

        errors = PipelineConfigurationCheck.call
        raise Agentic::Errors::ConfigurationError, errors.join("\n") if errors.any?
      end
    end
  end
end
