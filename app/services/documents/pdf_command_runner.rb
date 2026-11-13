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

    # Width and height in points (72 per inch) of the page area pdftoppm renders.
    def page_size(pdf_path, page_number:)
      output = run!("pdfinfo", "-f", page_number.to_s, "-l", page_number.to_s, "-box", pdf_path)
      match = output.match(/^Page\s+#{page_number}\s+MediaBox:\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s*$/)
      raise Agentic::Errors::ConfigurationError, "Could not determine PDF page size for page #{page_number}" unless match

      left, bottom, right, top = match.captures.map(&:to_f)
      [ (right - left).abs, (top - bottom).abs ]
    end

    def extract_text(pdf_path, page_number:)
      run!("pdftotext", "-f", page_number.to_s, "-l", page_number.to_s, "-layout", pdf_path, "-")
    end

    def render_page(pdf_path, page_number:, output_dir:, dpi:)
      prefix = File.join(output_dir, "page-#{page_number}")
      run!(
        "pdftoppm",
        "-f", page_number.to_s,
        "-l", page_number.to_s,
        "-singlefile",
        "-r", dpi.to_s,
        "-png",
        pdf_path,
        prefix
      )

      expected_path = "#{prefix}.png"
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
