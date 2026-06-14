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
      page = prepare_document_page(text)
      payload = build_payload(text)
      payload[:pages] = [ page_payload(page) ]

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

      def prepare_document_page(text)
        page = document.document_pages.find_or_initialize_by(page_number: 1)
        page.update!(
          account: document.account,
          embedded_text: text,
          ocr_text: "",
          metadata: {
            source: "text_upload"
          },
          status: :processed
        )

        document.document_pages.where.not(page_number: 1).destroy_all
        page
      end

      def page_payload(page)
        {
          id: page.id,
          number: page.page_number,
          embedded_text: page.embedded_text.to_s,
          ocr_text: page.ocr_text.to_s,
          image_attached: false,
          image_blob_id: nil,
          metadata: page.metadata
        }
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
