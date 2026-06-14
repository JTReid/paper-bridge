# frozen_string_literal: true

require "tmpdir"

module Documents
  class PreparePdf
    DEFAULT_DPI = 225

    def self.call(document, command_runner: PdfCommandRunner.new, dpi: DEFAULT_DPI)
      new(document, command_runner: command_runner, dpi: dpi).call
    end

    def initialize(document, command_runner:, dpi:)
      @document = document
      @command_runner = command_runner
      @dpi = dpi
    end

    def call
      validate_document_file!
      document.preparing!

      document.file.open do |pdf_file|
        prepare_from_path(pdf_file.path)
      end
    rescue StandardError => e
      document.update!(
        preparation_status: :preparation_failed,
        preparation_error: e.message
      )
      raise
    end

    private

      attr_reader :document, :command_runner, :dpi

      def validate_document_file!
        raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?
        return if document.content_type == Prepare::PDF_CONTENT_TYPE

        raise Agentic::Errors::ConfigurationError, "Unsupported PDF preparation content type: #{document.content_type}"
      end

      def prepare_from_path(pdf_path)
        Dir.mktmpdir("paper-bridge-pdf") do |work_dir|
          page_count = command_runner.page_count(pdf_path)
          pages = prepare_pages(pdf_path, work_dir, page_count)
          payload = build_payload(page_count, pages)

          document.document_pages.where.not(page_number: 1..page_count).destroy_all
          document.update!(
            preparation_status: :prepared,
            prepared_payload: payload,
            prepared_at: Time.current,
            preparation_error: nil
          )

          payload
        end
      end

      def prepare_pages(pdf_path, work_dir, page_count)
        (1..page_count).map do |page_number|
          prepare_page(pdf_path, work_dir, page_number)
        end
      end

      def prepare_page(pdf_path, work_dir, page_number)
        page = document.document_pages.find_or_initialize_by(page_number: page_number)
        page.assign_attributes(account: document.account, status: :processing)
        page.save!

        embedded_text = normalize_text(command_runner.extract_text(pdf_path, page_number: page_number))
        image_path = command_runner.render_page(pdf_path, page_number: page_number, output_dir: work_dir, dpi: dpi)
        ocr_text = normalize_text(command_runner.ocr_image(image_path))
        metadata = page_metadata(embedded_text, ocr_text)

        attach_page_image(page, image_path, page_number)
        page.update!(
          embedded_text: embedded_text,
          ocr_text: ocr_text,
          metadata: metadata,
          status: :processed
        )

        page_payload(page, metadata)
      rescue StandardError
        page.update!(status: :failed) if page&.persisted?
        raise
      end

      def attach_page_image(page, image_path, page_number)
        File.open(image_path, "rb") do |image|
          page.image.attach(
            io: image,
            filename: "#{document.id}-page-#{page_number}.png",
            content_type: "image/png"
          )
        end
      end

      def page_metadata(embedded_text, ocr_text)
        {
          dpi: dpi,
          embedded_word_count: word_count(embedded_text),
          ocr_word_count: word_count(ocr_text),
          selected_text_source: selected_text_source(embedded_text, ocr_text)
        }
      end

      def page_payload(page, metadata)
        {
          id: page.id,
          number: page.page_number,
          embedded_text: page.embedded_text.to_s,
          ocr_text: page.ocr_text.to_s,
          image_attached: page.image.attached?,
          image_blob_id: page.image.attached? ? page.image.blob_id : nil,
          metadata: metadata
        }
      end

      def build_payload(page_count, pages)
        warnings = []
        warnings << "No readable text found in embedded or OCR output." if pages.all? { |page| page[:embedded_text].blank? && page[:ocr_text].blank? }

        {
          format: "pdf",
          preparation_version: "pdf-v1",
          page_count: page_count,
          dpi: dpi,
          full_text: full_text(pages),
          pages: pages,
          warnings: warnings
        }
      end

      def full_text(pages)
        pages.map do |page|
          <<~TEXT.strip
            Page #{page[:number]}
            Embedded text:
            #{page[:embedded_text]}

            OCR text:
            #{page[:ocr_text]}
          TEXT
        end.join("\n\n")
      end

      def normalize_text(text)
        text.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip
      end

      def word_count(text)
        text.to_s.scan(/\S+/).count
      end

      def selected_text_source(embedded_text, ocr_text)
        return "combined" if embedded_text.present? && ocr_text.present?
        return "embedded" if embedded_text.present?
        return "ocr" if ocr_text.present?

        "none"
      end
  end
end
