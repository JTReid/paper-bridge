require "test_helper"
require "rack/mock"
require "rack/multipart"

class DocumentUploadMultipartTest < ActiveSupport::TestCase
  test "multipart parser accepts a batch of 128 document files" do
    parts = 128.times.map do |index|
      multipart_part("document[files][]", "Document #{index}", filename: "document-#{index}.txt")
    end

    parse_multipart(parts) do |params|
      files = params.fetch("document").fetch("files")

      assert_equal 128, files.length
      files.each_with_index do |file, index|
        assert_equal "document-#{index}.txt", file.fetch(:filename)
        assert_equal "Document #{index}", file.fetch(:tempfile).read
      end
    end
  end

  test "multipart parser accepts more than 4096 total form parts" do
    parts = [ multipart_part("document[files][]", "Document contents", filename: "document.txt") ]
    parts.concat(4096.times.map { |index| multipart_part("document[notes][]", "Note #{index}") })

    parse_multipart(parts) do |params|
      document = params.fetch("document")
      assert_equal 1, document.fetch("files").length
      assert_equal "Document contents", document.fetch("files").first.fetch(:tempfile).read
      assert_equal 4096.times.map { |index| "Note #{index}" }, document.fetch("notes")
    end
  end

  private

  def multipart_part(name, content, filename: nil)
    disposition = "Content-Disposition: form-data; name=\"#{name}\""
    disposition += "; filename=\"#{filename}\"" if filename
    headers = [ disposition ]
    headers << "Content-Type: text/plain" if filename
    "#{headers.join("\r\n")}\r\n\r\n#{content}\r\n"
  end

  def parse_multipart(parts)
    boundary = "paper-bridge-document-upload"
    body = parts.map { |part| "--#{boundary}\r\n#{part}" }.join
    body += "--#{boundary}--\r\n"
    env = Rack::MockRequest.env_for(
      "/documents", method: "POST", input: body,
      "CONTENT_TYPE" => "multipart/form-data; boundary=#{boundary}"
    )

    yield Rack::Multipart.parse_multipart(env)
  ensure
    Array(env && env["rack.tempfiles"]).each(&:close!)
  end
end
