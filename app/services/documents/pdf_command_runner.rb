# frozen_string_literal: true

require "open3"

module Documents
  class PdfCommandRunner
    def page_count(pdf_path)
      output = run!("pdfinfo", pdf_path)
      match = output.match(/^Pages:\s+(\d+)$/)
      raise Agentic::Errors::ConfigurationError, "Could not determine PDF page count" unless match

      match[1].to_i
    end

    def extract_text(pdf_path, page_number:)
      run!("pdftotext", "-f", page_number.to_s, "-l", page_number.to_s, "-layout", pdf_path, "-")
    end

    def render_page(pdf_path, page_number:, output_dir:, dpi:)
      prefix = File.join(output_dir, "page")
      run!(
        "pdftoppm",
        "-f", page_number.to_s,
        "-l", page_number.to_s,
        "-r", dpi.to_s,
        "-png",
        pdf_path,
        prefix
      )

      expected_path = "#{prefix}-#{page_number}.png"
      return expected_path if File.exist?(expected_path)

      raise Agentic::Errors::ConfigurationError, "PDF page image was not rendered for page #{page_number}"
    end

    def ocr_image(image_path)
      run!("tesseract", image_path, "stdout")
    end

    private

      def run!(*command)
        stdout, stderr, status = Open3.capture3(*command)
        return stdout if status.success?

        raise Agentic::Errors::ExecutionError, "#{command.first} failed: #{stderr.presence || stdout}"
      rescue Errno::ENOENT
        raise Agentic::Errors::ConfigurationError, "#{command.first} is not installed or is not on PATH"
      end
  end
end
