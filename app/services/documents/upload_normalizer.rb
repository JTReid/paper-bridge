# frozen_string_literal: true

require "marcel"
require "tempfile"
require "vips"

module Documents
  class UploadNormalizer
    IMAGE_CONTENT_TYPES = %w[
      image/jpeg
      image/png
      image/webp
      image/heic
      image/heif
      image/tiff
    ].freeze
    JPEG_CONVERSION_CONTENT_TYPES = %w[image/heic image/heif image/tiff].freeze
    PASS_THROUGH_CONTENT_TYPES = (
      [ Prepare::PDF_CONTENT_TYPE ] + Prepare::TEXT_CONTENT_TYPES
    ).freeze
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .webp .heic .heif .tif .tiff].freeze
    JPEG_QUALITY = 92
    MAX_SOURCE_IMAGE_BYTES = 50.megabytes
    MAX_STORED_IMAGE_BYTES = 15.megabytes
    MAX_IMAGE_PIXELS = 40_000_000

    ACCEPT_ATTRIBUTE = [
      ".pdf",
      ".txt",
      ".csv",
      ".md",
      ".markdown",
      ".json",
      *IMAGE_EXTENSIONS,
      *PASS_THROUGH_CONTENT_TYPES,
      *IMAGE_CONTENT_TYPES
    ].uniq.join(",")

    class Error < StandardError; end
    class UnsupportedTypeError < Error; end
    class InvalidImageError < Error; end
    class MultipleImagesError < Error; end
    class ImageTooLargeError < Error; end

    Result = Struct.new(:attachable, :temporary_file, keyword_init: true) do
      def close
        temporary_file&.close!
      end
    end

    def self.call(upload)
      new(upload).call
    end

    def initialize(upload)
      @upload = upload
    end

    def call
      validate_upload!
      content_type = detected_content_type

      if image_upload? && !IMAGE_CONTENT_TYPES.include?(content_type)
        raise UnsupportedTypeError, "has an unsupported image type" if content_type.start_with?("image/")

        raise InvalidImageError, "does not contain a valid image"
      end

      return Result.new(attachable: upload) if PASS_THROUGH_CONTENT_TYPES.include?(content_type)

      unless IMAGE_CONTENT_TYPES.include?(content_type)
        raise UnsupportedTypeError, "has an unsupported file type"
      end

      validate_source_size!(content_type)
      image = load_image
      reject_multiple_images!(image)
      validate_dimensions!(image)

      if JPEG_CONVERSION_CONTENT_TYPES.include?(content_type)
        convert_to_jpeg(image)
      else
        verify_pixels!(image)
        validate_stored_size!(upload_byte_size)
        Result.new(attachable: image_attachable(content_type))
      end
    rescue Vips::Error
      raise InvalidImageError, "does not contain a valid image"
    ensure
      rewind_io
    end

    private

      attr_reader :upload

      def validate_upload!
        return if upload_io.respond_to?(:read)

        raise UnsupportedTypeError, "has an unsupported file type"
      end

      def detected_content_type
        rewind_io
        Marcel::MimeType.for(upload_io, name: original_filename, declared_type: declared_content_type)
      ensure
        rewind_io
      end

      def declared_content_type
        upload.content_type.to_s.downcase.split(";", 2).first if upload.respond_to?(:content_type)
      end

      def image_upload?
        declared_content_type.to_s.start_with?("image/") || IMAGE_EXTENSIONS.include?(File.extname(original_filename).downcase)
      end

      def load_image
        if upload_io.respond_to?(:path) && File.file?(upload_io.path.to_s)
          Vips::Image.new_from_file(upload_io.path.to_s, access: :sequential, fail_on: :error)
        else
          rewind_io
          Vips::Image.new_from_buffer(upload_io.read, "", access: :sequential, fail_on: :error)
        end
      end

      def reject_multiple_images!(image)
        page_count = image.get_typeof("n-pages").zero? ? 1 : image.get("n-pages").to_i
        return if page_count == 1

        raise MultipleImagesError, "must contain exactly one image"
      end

      def verify_pixels!(image)
        image.avg
      end

      def convert_to_jpeg(image)
        temporary_file = Tempfile.new([ "paper-bridge-image-", ".jpg" ])
        temporary_file.binmode

        jpeg_image = image.autorot.colourspace(:srgb)
        jpeg_image = jpeg_image.flatten(background: [ 255, 255, 255 ]) if jpeg_image.has_alpha?
        jpeg_image.jpegsave(
          temporary_file.path,
          Q: JPEG_QUALITY,
          strip: true,
          optimize_coding: true
        )
        validate_stored_size!(File.size(temporary_file.path))
        temporary_file.rewind

        Result.new(
          attachable: {
            io: temporary_file,
            filename: jpeg_filename,
            content_type: "image/jpeg"
          },
          temporary_file: temporary_file
        )
      rescue StandardError
        temporary_file&.close!
        raise
      end

      def image_attachable(content_type)
        rewind_io
        {
          io: upload_io,
          filename: original_filename,
          content_type: content_type
        }
      end

      def validate_source_size!(content_type)
        limit = if JPEG_CONVERSION_CONTENT_TYPES.include?(content_type)
          MAX_SOURCE_IMAGE_BYTES
        else
          MAX_STORED_IMAGE_BYTES
        end
        return if upload_byte_size <= limit

        raise ImageTooLargeError, "must be smaller than #{limit / 1.megabyte} MB"
      end

      def validate_stored_size!(byte_size)
        return if byte_size <= MAX_STORED_IMAGE_BYTES

        raise ImageTooLargeError, "must be smaller than #{MAX_STORED_IMAGE_BYTES / 1.megabyte} MB after normalization"
      end

      def validate_dimensions!(image)
        return if image.width * image.height <= MAX_IMAGE_PIXELS

        raise ImageTooLargeError, "has dimensions that are too large"
      end

      def upload_byte_size
        return upload_io.size if upload_io.respond_to?(:size)
        return File.size(upload_io.path) if upload_io.respond_to?(:path)

        raise UnsupportedTypeError, "has an unsupported file type"
      end

      def jpeg_filename
        basename = File.basename(original_filename)
        stem = basename.delete_suffix(File.extname(basename)).presence || "upload"
        "#{stem}.jpg"
      end

      def original_filename
        filename = upload.original_filename.to_s if upload.respond_to?(:original_filename)
        filename.presence || "upload"
      end

      def upload_io
        @upload_io ||= upload.respond_to?(:tempfile) ? upload.tempfile : upload
      end

      def rewind_io
        upload_io.rewind if upload_io.respond_to?(:rewind)
      end
  end
end
