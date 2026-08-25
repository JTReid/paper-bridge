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
