# frozen_string_literal: true

module Agents
  class StructuredTextValidator
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      call
      set_response
      response
    end

    def requirements
      {
        model: llm.name,
        system: prompt.system_directive,
        prompt: content.to_json,
        max_tokens: 1_000,
        response_format: "structured_json",
        schema_name: "structured_validation"
      }
    end

    def step_started
      "Validating structured output"
    end

    def step_complete
      "Validation complete"
    end

    def pass_through_pipeline_response?
      true
    end

    def set_response
      @response = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      log_activity(
        action: "structured_text_validated",
        message: response["status"] == "APPROVED" ? "Structured output approved" : "Structured output rejected",
        metadata: response
      )
    end
  end
end
