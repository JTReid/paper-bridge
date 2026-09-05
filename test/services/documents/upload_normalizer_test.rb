require "test_helper"
require "tempfile"
require "vips"

module Documents
  class UploadNormalizerTest < ActiveSupport::TestCase
    test "passes existing PDF and text uploads through unchanged" do
      [
        [ "%PDF-1.4\n% test", "record.pdf", "application/pdf" ],
        [ "plain text", "record.txt", "text/plain" ],
        [ "date,event\n2026-09-05,Review", "record.csv", "text/csv" ],
        [ "# Review\nCare notes", "record.md", "text/markdown" ],
        [ '{"kind":"record"}', "record.json", "application/json" ]
      ].each do |bytes, filename, content_type|
        with_upload(bytes, filename: filename, content_type: content_type) do |upload|
          result = UploadNormalizer.call(upload)

          assert_same upload, result.attachable
          assert_nil result.temporary_file
          assert UploadNormalizer.processable_content_type?(content_type)
        end
      end
    end

    test "keeps JPEG PNG and WebP image bytes in their browser-compatible formats" do
      {
        ".jpg" => "image/jpeg",
        ".png" => "image/png",
        ".webp" => "image/webp"
      }.each do |extension, content_type|
        bytes = test_image.write_to_buffer(extension)

        with_upload(bytes, filename: "prescription#{extension}", content_type: "application/octet-stream") do |upload|
          result = UploadNormalizer.call(upload)

          assert_equal "prescription#{extension}", result.attachable.fetch(:filename)
          assert_equal content_type, result.attachable.fetch(:content_type)
          assert_same upload.tempfile, result.attachable.fetch(:io)
          assert_equal bytes, result.attachable.fetch(:io).read
        ensure
          result&.close
        end
      end
    end

    test "converts HEIC HEIF and TIFF images to high-quality JPEG attachments" do
      [
        [ ".heic", "image/heic" ],
        [ ".heif", "image/heif" ],
        [ ".tiff", "image/tiff" ]
      ].each do |extension, content_type|
        bytes = test_image.write_to_buffer(extension)

        with_upload(bytes, filename: "handwritten-prescription#{extension}", content_type: content_type) do |upload|
          result = UploadNormalizer.call(upload)
          converted_file = result.temporary_file
          converted_path = converted_file.path

          assert_equal "handwritten-prescription.jpg", result.attachable.fetch(:filename)
          assert_equal "image/jpeg", result.attachable.fetch(:content_type)
          assert_equal [ 0xff, 0xd8, 0xff ], result.attachable.fetch(:io).read(3).bytes
          assert_equal [ 12, 8 ], jpeg_dimensions(result.attachable.fetch(:io))

          result.close
          assert_predicate converted_file, :closed?
          assert_not File.exist?(converted_path)
        end
      end
    end

    test "rejects multi-image TIFF uploads instead of dropping later pages" do
      bytes = multi_image_tiff

      with_upload(bytes, filename: "two-pages.tiff", content_type: "image/tiff") do |upload|
        error = assert_raises(UploadNormalizer::MultipleImagesError) { UploadNormalizer.call(upload) }

        assert_equal "must contain exactly one image", error.message
      end
    end

    test "rejects an invalid upload that claims to be an image" do
      with_upload("not really a jpeg", filename: "prescription.jpg", content_type: "image/jpeg") do |upload|
        error = assert_raises(UploadNormalizer::InvalidImageError) { UploadNormalizer.call(upload) }

        assert_equal "does not contain a valid image", error.message
      end
    end

    test "preserves storage-only files without image parsing or later attachment analysis" do
      [
        [ '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>', "record.svg", "image/svg+xml" ],
        [ "GIF89a\x01\x00\x01\x00", "record.gif", "image/gif" ],
        [ "PK\x03\x04archive-content", "record.zip", "application/zip" ],
        [ "PK\x03\x04word-content", "record.docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
        [ "word-document-content", "record.doc", "application/msword" ],
        [ "\x00\x01unknown-content", "record.custom", "application/octet-stream" ]
      ].each do |bytes, filename, content_type|
        with_upload(bytes, filename: filename, content_type: content_type) do |upload|
          normalizer = UploadNormalizer.new(upload)
          normalizer.define_singleton_method(:load_image) { raise "Storage-only uploads must not be decoded" }

          result = normalizer.call

          assert_equal filename, result.attachable.fetch(:filename)
          assert_equal content_type, result.attachable.fetch(:content_type)
          assert_same upload.tempfile, result.attachable.fetch(:io)
          assert_equal bytes.b, result.attachable.fetch(:io).read
          assert_equal false, result.attachable.fetch(:identify)
          assert_equal true, result.attachable.dig(:metadata, :analyzed)
          assert_nil result.temporary_file
          assert_not UploadNormalizer.processable_content_type?(content_type)
        end
      end
    end

    test "uses detected storage-only MIME instead of the upload declared type" do
      bytes = "PK\x03\x04archive-content"

      with_upload(bytes, filename: "record.zip", content_type: "application/octet-stream") do |upload|
        result = UploadNormalizer.call(upload)

        assert_equal "application/zip", result.attachable.fetch(:content_type)
        assert_equal false, result.attachable.fetch(:identify)
        assert_equal bytes, result.attachable.fetch(:io).read
      end
    end

    test "does not treat unsupported image bytes as a valid supported image upload" do
      svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"></svg>'

      with_upload(svg, filename: "record.png", content_type: "image/png") do |upload|
        assert_raises(UploadNormalizer::InvalidImageError) { UploadNormalizer.call(upload) }
      end
    end

    test "only the existing PDF text and image types are processable" do
      (UploadNormalizer::PASS_THROUGH_CONTENT_TYPES + UploadNormalizer::IMAGE_CONTENT_TYPES).each do |content_type|
        assert UploadNormalizer.processable_content_type?(content_type)
      end

      [ nil, "", "image/svg+xml", "image/gif", "application/zip", "application/msword", "video/mp4", "audio/mpeg" ].each do |content_type|
        assert_not UploadNormalizer.processable_content_type?(content_type)
      end
    end

    test "rejects browser image uploads above the stored byte limit" do
      bytes = test_image.write_to_buffer(".png")

      with_upload(bytes, filename: "oversized.png", content_type: "image/png") do |upload|
        upload.tempfile.define_singleton_method(:size) { UploadNormalizer::MAX_STORED_IMAGE_BYTES + 1 }

        error = assert_raises(UploadNormalizer::ImageTooLargeError) { UploadNormalizer.call(upload) }

        assert_equal "must be smaller than 15 MB", error.message
      end
    end

    test "rejects images above the decoded pixel limit before evaluating pixels" do
      bytes = test_image.write_to_buffer(".png")

      with_upload(bytes, filename: "too-many-pixels.png", content_type: "image/png") do |upload|
        normalizer = UploadNormalizer.new(upload)
        normalizer.define_singleton_method(:load_image) { Vips::Image.black(8_000, 5_001) }

        error = assert_raises(UploadNormalizer::ImageTooLargeError) { normalizer.call }

        assert_equal "has dimensions that are too large", error.message
      end
    end

    private

      def test_image
        @test_image ||= Vips::Image.black(12, 8, bands: 3) + [ 35, 90, 140 ]
      end

      def multi_image_tiff
        first = test_image
        second = test_image + [ 15, 15, 15 ]
        joined = Vips::Image.arrayjoin([ first, second ], across: 1)
        joined.set_type(GObject::GINT_TYPE, "page-height", first.height)
        joined.write_to_buffer(".tiff", page_height: first.height)
      end

      def jpeg_dimensions(io)
        io.rewind
        image = Vips::Image.new_from_buffer(io.read, "")
        [ image.width, image.height ]
      ensure
        io.rewind
      end

      def with_upload(bytes, filename:, content_type:)
        Tempfile.create([ "paper-bridge-upload-", File.extname(filename) ]) do |file|
          file.binmode
          file.write(bytes)
          file.rewind

          upload = ActionDispatch::Http::UploadedFile.new(
            tempfile: file,
            filename: filename,
            type: content_type
          )
          yield upload
        end
      end
  end
end
