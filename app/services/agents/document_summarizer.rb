# frozen_string_literal: true

require "base64"

module Agents
  class DocumentSummarizer
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    MAX_INPUT_BYTES = 200_000

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
      validate_prepared_document!

      @content = normalize_content(prompt_content_from_payload)

      if content.blank?
        raise Agentic::Errors::ConfigurationError, "Prepared document did not contain readable text or page images" unless pdf_with_page_images?

        @content = "PDF contains no readable extracted text. Use the attached page screenshots as the primary source."
      end

      log_activity(
        action: "prepared_document_loaded",
        message: "Prepared document payload loaded",
        metadata: {
          document_id: document.id,
          filename: document.original_filename,
          content_type: document.content_type,
          byte_size: document.byte_size,
          preparation_version: prepared_payload["preparation_version"],
          page_count: prepared_payload["page_count"],
          image_page_count: image_page_count,
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

      def validate_prepared_document!
        raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?
        raise Agentic::Errors::ConfigurationError, "Document has not been prepared" unless document.prepared?
        raise Agentic::Errors::ConfigurationError, "Prepared document payload is missing" if prepared_payload.blank?
      end

      def prepared_payload
        @prepared_payload ||= document.prepared_payload.with_indifferent_access
      end

      def prepared_pdf?
        prepared_payload["format"] == "pdf"
      end

      def pdf_with_page_images?
        prepared_pdf? && image_page_count.positive?
      end

      def image_page_count
        return 0 unless prepared_pdf?

        document_pages_by_number.values.count { |page| page.image.attached? }
      end

      def normalize_content(raw_content)
        raw_content.to_s
                   .byteslice(0, MAX_INPUT_BYTES)
                   .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                   .strip
      end

      def prompt_content
        return pdf_prompt_content if prepared_pdf?

        <<~TEXT
          Filename: #{document.original_filename}
          Content type: #{document.content_type}
          Preparation version: #{prepared_payload["preparation_version"]}

          Prepared document text:
          #{content}
        TEXT
      end

      def pdf_prompt_content
        content_blocks = [
          {
            type: "text",
            text: <<~TEXT
              Filename: #{document.original_filename}
              Content type: #{document.content_type}
              Preparation version: #{prepared_payload["preparation_version"]}
              Page screenshots are attached in page order. Use both the extracted text and the screenshots when summarizing.
            TEXT
          }
        ]

        prepared_pages.each do |page|
          content_blocks << {
            type: "text",
            text: pdf_page_text(page)
          }

          image_content = pdf_page_image_content(page)
          content_blocks << image_content if image_content.present?
        end

        content_blocks
      end

      def prompt_content_from_payload
        case prepared_payload["format"]
        when "pdf"
          pdf_text_content
        when "text"
          prepared_payload["full_text"].to_s
        else
          prepared_payload["full_text"].to_s
        end
      end

      def pdf_text_content
        prepared_pages.map { |page| pdf_page_text(page) }.join("\n\n")
      end

      def prepared_pages
        @prepared_pages ||= Array(prepared_payload["pages"])
      end

      def pdf_page_text(page)
        <<~TEXT.strip
          Page #{page["number"]}
          Embedded text:
          #{page["embedded_text"]}

          OCR text:
          #{page["ocr_text"]}
        TEXT
      end

      def pdf_page_image_content(page)
        page_record = document_pages_by_number[page["number"].to_i]
        return unless page_record&.image&.attached?

        {
          type: "image_url",
          image_url: {
            url: image_data_url(page_record),
            detail: "auto"
          }
        }
      end

      def document_pages_by_number
        @document_pages_by_number ||= document.document_pages
                                             .includes(image_attachment: :blob)
                                             .index_by(&:page_number)
      end

      def image_data_url(page_record)
        content_type = page_record.image.blob.content_type.presence || "image/png"
        base64 = Base64.strict_encode64(page_record.image.download)

        "data:#{content_type};base64,#{base64}"
      end
  end
end
