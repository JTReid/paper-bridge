require "tmpdir"
require "test_helper"

class Documents::PdfCommandRunnerTest < ActiveSupport::TestCase
  class SimulatedPopplerRunner < Documents::PdfCommandRunner
    attr_reader :command

    private

      def run!(*command)
        @command = command
        output_prefix = command.last
        output_path = if command.include?("-singlefile")
          "#{output_prefix}.png"
        else
          "#{output_prefix}-01.png"
        end

        File.binwrite(output_path, "simulated PNG")
      end
  end

  class SimulatedPdfinfoRunner < Documents::PdfCommandRunner
    attr_reader :command

    def initialize(output)
      @output = output
    end

    private

      def run!(*command)
        @command = command
        @output
      end
  end

  test "reads a page size from the media box that pdftoppm renders" do
    runner = SimulatedPdfinfoRunner.new(<<~OUTPUT)
      Page   12 size:  500 x 500 pts
      Page   12 rot:   0
      Page   12 MediaBox:      0.00     0.00  1935.00  2540.00
      Page   12 CropBox:      10.00    10.00   510.00   510.00
    OUTPUT

    assert_equal [ 1935.0, 2540.0 ], runner.page_size("poster.pdf", page_number: 12)
    assert_equal [ "pdfinfo", "-f", "12", "-l", "12", "-box", "poster.pdf" ], runner.command
  end

  test "fails clearly when a page size cannot be read" do
    runner = SimulatedPdfinfoRunner.new("Pages: 1\n")

    error = assert_raises(Agentic::Errors::ConfigurationError) do
      runner.page_size("unreadable.pdf", page_number: 1)
    end
    assert_equal "Could not determine PDF page size for page 1", error.message
  end

  test "renders a requested page to a deterministic filename" do
    runner = SimulatedPopplerRunner.new

    Dir.mktmpdir("pdf-command-runner-test") do |output_dir|
      path = runner.render_page(
        "sixteen-page-document.pdf",
        page_number: 1,
        output_dir: output_dir,
        dpi: 300
      )

      assert_equal File.join(output_dir, "page-1.png"), path
      assert_path_exists path
      assert_equal [
        "pdftoppm",
        "-f", "1",
        "-l", "1",
        "-singlefile",
        "-r", "300",
        "-png",
        "sixteen-page-document.pdf",
        File.join(output_dir, "page-1")
      ], runner.command
    end
  end
end
