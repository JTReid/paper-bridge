# frozen_string_literal: true

module Documents
  class PrepareText
    MAX_INPUT_BYTES = 200_000

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      validate_document_file!
      document.preparing!

      text = normalize_content(document.file.download)
      payload = build_payload(text)

      document.update!(
        preparation_status: :prepared,
        prepared_payload: payload,
        prepared_at: Time.current,
        preparation_error: nil
      )

      payload
    end

    private

      attr_reader :document

      def validate_document_file!
        raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?
      end

      def normalize_content(raw_content)
        raw_content.to_s
                   .byteslice(0, MAX_INPUT_BYTES)
                   .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
                   .strip
      end

      def build_payload(text)
        warnings = []
        warnings << "No readable text found." if text.blank?

        {
          format: "text",
          preparation_version: "text-v1",
          full_text: text,
          pages: [],
          warnings: warnings
        }
      end
  end
end
