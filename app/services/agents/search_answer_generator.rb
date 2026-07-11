# frozen_string_literal: true

module Agents
  class SearchAnswerGenerator
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      if search_results.empty?
        set_empty_response
      else
        call
        set_response
      end

      response
    end

    def requirements
      {
        model: llm.name,
        system: prompt.system_directive,
        prompt: answer_prompt,
        max_tokens: 1_200,
        response_format: "structured_json",
        schema_name: "search_answer"
      }
    end

    def step_started
      "Synthesizing search answer"
    end

    def step_complete
      "Search answer synthesized"
    end

    def setup_content
      @query = data.dig(:context, :query).to_s.strip
      @search_results = Array(data.dig(:context, :search_results))
      @content = evidence_text.presence || "No evidence chunks were retrieved."

      raise Agentic::Errors::ConfigurationError, "context[:query] is required" if query.blank?
    end

    def agent_type_name
      "search_answer_generator"
    end

    def set_response
      parsed_response = JSON.parse(provider.parse_response(raw_response)).deep_symbolize_keys
      @response = Documents::SearchAnswerCitationNormalizer.new(
        response: parsed_response,
        search_results: search_results
      ).call
      data[:context][:search_answer] = response

      log_activity(
        action: "search_answer_synthesized",
        message: "Search answer synthesized from retrieved chunks",
        metadata: response.except(:answer)
      )
    end

    private

      attr_reader :query, :search_results

      def set_empty_response
        @response = {
          answer: "I couldn’t find an answer to that question in these documents.",
          citations: [],
          limitations: [ "The documents available to you may not include the information needed to answer this question." ]
        }
        data[:context][:search_answer] = response

        log_activity(
          action: "search_answer_skipped",
          message: "Search answer synthesis skipped because no evidence chunks were retrieved",
          metadata: response
        )
      end

      def answer_prompt
        <<~PROMPT
          User question:
          #{query}

          Evidence chunks:
          #{evidence_text}

          Answer the user question using only the evidence chunks above.
          Cite every material claim with one or more source numbers in square brackets, such as [1] or [1, 2].
          In each structured citation, put that same source number in the chunk_id field.
          Use only source numbers listed below. Never expose database IDs.
          If the evidence is incomplete, state the limitation instead of guessing.
          Write for a parent or caregiver in plain language.
          Explain necessary medical or educational terms briefly.
          Outside the required source markers, never mention chunks, embeddings, retrieval, IDs, pipelines, models, or other system internals.
        PROMPT
      end

      def evidence_text
        @evidence_text ||= search_results.each_with_index.map do |result, index|
          <<~EVIDENCE
            Source #{index + 1}
            document_title: #{result.document.title}
            page_number: #{result.page.page_number}
            content:
            #{result.chunk.content}
          EVIDENCE
        end.join("\n")
      end
  end
end
