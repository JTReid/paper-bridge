# frozen_string_literal: true

module Agents
  class DocumentSummarizer
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    MAX_INPUT_BYTES = 200_000
    SUPPORTED_CONTENT_TYPES = [
      "application/json",
      "text/csv",
      "text/markdown",
      "text/plain"
    ].freeze

    def execute
      call
      set_response
      response
    end

    def requirements
      {
        model: llm.name,
        system: prompt.system_directive,
        prompt: prompt_content,
        max_tokens: 1_500,
        response_format: "structured_json",
        schema_name: "document_summary"
      }
    end

    def step_started
      "Summarizing uploaded document"
    end

    def step_complete
      "Document summary complete"
    end

    def setup_content
      @document = locate_document!
      validate_document_file!

      raw_content = document.file.download
      @content = normalize_content(raw_content)

      raise Agentic::Errors::ConfigurationError, "Uploaded document did not contain readable text" if content.blank?

      log_activity(
        action: "document_text_loaded",
        message: "Uploaded document text loaded",
        metadata: {
          document_id: document.id,
          filename: document.original_filename,
          content_type: document.content_type,
          byte_size: document.byte_size,
          extracted_bytes: content.bytesize
        }
      )
    end

    def set_response
      @response = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      log_activity(
        action: "document_summarized",
        message: "Document summary generated",
        metadata: response
      )
    end

    private

      attr_reader :document

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end

      def validate_document_file!
        raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?

        return if SUPPORTED_CONTENT_TYPES.include?(document.content_type)

        raise Agentic::Errors::ConfigurationError, "Unsupported document content type: #{document.content_type}"
      end

      def normalize_content(raw_content)
        raw_content.to_s
                   .byteslice(0, MAX_INPUT_BYTES)
                   .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                   .strip
      end

      def prompt_content
        <<~TEXT
          Filename: #{document.original_filename}
          Content type: #{document.content_type}

          Document text:
          #{content}
        TEXT
      end
  end
end
