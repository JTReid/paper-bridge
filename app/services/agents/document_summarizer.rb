# frozen_string_literal: true

module Agents
  class DocumentSummarizer
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
        prompt: summary_prompt,
        max_tokens: 2_000,
        response_format: "structured_json",
        schema_name: "document_summary"
      }
    end

    def step_started
      "Summarizing document chunks"
    end

    def step_complete
      "Document summary complete"
    end

    def setup_content
      @document = locate_document!
      @chunks = document.document_chunks.includes(:document_page).order(:chunk_index).to_a
      @content = evidence_text

      raise Agentic::Errors::ConfigurationError, "Document has no chunks to summarize" if chunks.empty?
    end

    def agent_type_name
      "document_summarizer"
    end

    def set_response
      parsed = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      @response = parsed.merge(
        metadata: {
          source: "document_summarizer",
          chunk_count: chunks.count
        }
      )

      Document.transaction do
        document.complete_initial_metadata!(category: parsed[:category], description: parsed[:description])
        document.update!(
          summary: response,
          summarized_at: Time.current
        )
      end

      log_activity(
        action: "document_summarized",
        message: "Document summary generated",
        metadata: response
      )
    end

    private

      attr_reader :document, :chunks

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end

      def summary_prompt
        <<~PROMPT
          Document title: #{document.title}
          Original filename: #{document.original_filename}
          Dependent: #{document.dependent.name}

          Summarize the document from the evidence chunks below.
          Keep the summary source-grounded and concise.
          Include the most important facts, decisions, dates, services, needs, and follow-up items when they are present.
          Do not infer facts that are not supported by the evidence.
          Write for a parent or caregiver in plain language.
          Explain necessary medical or educational terms briefly.
          Never mention chunks, embeddings, retrieval, IDs, pipelines, models, or other system internals.
          #{Documents::MetadataSchemas::INSTRUCTIONS}

          Evidence chunks:
          #{content}
        PROMPT
      end

      def evidence_text
        chunks.map { |chunk| evidence_entry(chunk) }.join("\n")
      end

      def evidence_entry(chunk)
        <<~EVIDENCE
          document_chunk_id: #{chunk.id}
          chunk_index: #{chunk.chunk_index}
          page_number: #{chunk.document_page.page_number}
          label: #{chunk.label}
          content:
          #{chunk.content}
        EVIDENCE
      end
  end
end
