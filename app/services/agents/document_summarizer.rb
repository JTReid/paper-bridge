# frozen_string_literal: true

module Agents
  class DocumentSummarizer
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    MAX_EVIDENCE_CHARS = 60_000

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
          chunk_count: chunks.count,
          evidence_truncated: evidence_truncated
        }
      )

      document.update!(
        summary: response,
        summarized_at: Time.current
      )

      log_activity(
        action: "document_summarized",
        message: "Document summary generated",
        metadata: response
      )
    end

    private

      attr_reader :document, :chunks, :evidence_truncated

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
          Category: #{document.category}
          Dependent: #{document.dependent.name}

          Summarize the document from the evidence chunks below.
          Keep the summary source-grounded and concise.
          Include the most important facts, decisions, dates, services, needs, and follow-up items when they are present.
          Do not infer facts that are not supported by the evidence.
          #{truncation_notice}

          Evidence chunks:
          #{content}
        PROMPT
      end

      def truncation_notice
        return unless evidence_truncated

        "Only the first #{MAX_EVIDENCE_CHARS} characters of chunk evidence are included because this document is large."
      end

      def evidence_text
        used_chars = 0
        @evidence_truncated = false

        entries = chunks.filter_map do |chunk|
          entry = evidence_entry(chunk)
          remaining_chars = MAX_EVIDENCE_CHARS - used_chars

          if remaining_chars <= 0
            @evidence_truncated = true
            next
          end

          if entry.length > remaining_chars
            @evidence_truncated = true
            used_chars += remaining_chars
            entry[0, remaining_chars]
          else
            used_chars += entry.length
            entry
          end
        end

        entries.join("\n")
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
