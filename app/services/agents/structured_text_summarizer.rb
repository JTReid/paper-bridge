# frozen_string_literal: true

module Agents
  class StructuredTextSummarizer
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
        prompt: content,
        max_tokens: 2_000,
        response_format: "structured_json",
        schema_name: "structured_summary"
      }
    end

    def step_started
      "Summarizing source text"
    end

    def step_complete
      "Summary complete"
    end

    def set_response
      @response = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      log_activity(action: "structured_text_summarized", message: "Structured text summary generated", metadata: response)
    end
  end
end
