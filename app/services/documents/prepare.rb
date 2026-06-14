# frozen_string_literal: true

module Documents
  class Prepare
    TEXT_CONTENT_TYPES = [
      "application/json",
      "text/csv",
      "text/markdown",
      "text/plain"
    ].freeze

    PDF_CONTENT_TYPE = "application/pdf"

    def self.call(document, pdf_command_runner: PdfCommandRunner.new)
      new(document, pdf_command_runner: pdf_command_runner).call
    end

    def initialize(document, pdf_command_runner:)
      @document = document
      @pdf_command_runner = pdf_command_runner
    end

    def call
      case document.content_type
      when PDF_CONTENT_TYPE
        PreparePdf.call(document, command_runner: pdf_command_runner)
      when *TEXT_CONTENT_TYPES
        PrepareText.call(document)
      else
        raise Agentic::Errors::ConfigurationError, "Unsupported document content type: #{document.content_type}"
      end
    end

    private

      attr_reader :document, :pdf_command_runner
  end
end
