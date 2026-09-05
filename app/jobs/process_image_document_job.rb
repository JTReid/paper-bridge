# frozen_string_literal: true

class ProcessImageDocumentJob < ApplicationJob
  queue_as :default

  NORMALIZED_IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  class_attribute :llm_connection, default: RestClient

  retry_on Agentic::Errors::ExecutionError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(document)
    return unless document.processable? && Documents::UploadNormalizer::IMAGE_CONTENT_TYPES.include?(document.content_type)

    document.processing!
    prepared_payload = prepare_image(document)
    pipeline_run = create_pipeline_run(document, prepared_payload)

    Agentic::ImageDocumentIngestionPipeline.new(
      connection: llm_connection,
      context: pipeline_context(document, pipeline_run)
    ).execute

    document.reload.update!(status: :processed)
  rescue Agentic::Errors::ConfigurationError => e
    mark_document_failed(document, e)
  rescue StandardError => e
    mark_document_failed(document, e)
    raise
  end

  private

    def prepare_image(document)
      validate_image!(document)
      document.preparing!

      page = document.document_pages.find_or_initialize_by(page_number: 1)
      page.update!(
        account: document.account,
        embedded_text: "",
        ocr_text: "",
        metadata: {
          source: "image_upload",
          content_type: document.file.blob.content_type,
          filename: document.file.blob.filename.to_s
        },
        status: :processing
      )
      page.image.attach(document.file.blob) unless page.image.blob_id == document.file.blob_id

      document.document_pages.where.not(id: page.id).destroy_all

      payload = {
        format: "image",
        preparation_version: "image-v1",
        page_count: 1,
        full_text: "",
        extracted_text: "",
        pages: [ page_payload(page) ],
        warnings: []
      }

      document.update!(
        preparation_status: :prepared,
        prepared_payload: payload,
        prepared_at: Time.current,
        preparation_error: nil
      )

      payload
    end

    def validate_image!(document)
      raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?
      return if NORMALIZED_IMAGE_CONTENT_TYPES.include?(document.file.blob.content_type)

      raise Agentic::Errors::ConfigurationError, "Image document was not normalized before processing: #{document.file.blob.content_type}"
    end

    def page_payload(page)
      {
        id: page.id,
        number: page.page_number,
        embedded_text: "",
        ocr_text: "",
        image_attached: page.image.attached?,
        image_blob_id: page.image.blob_id,
        metadata: page.metadata
      }
    end

    def create_pipeline_run(document, prepared_payload)
      PipelineRun.create!(
        subject: document,
        user: document.user,
        context: {
          document_id: document.id,
          account_id: document.account_id,
          filename: document.original_filename,
          content_type: document.content_type,
          byte_size: document.byte_size,
          preparation_status: document.preparation_status,
          preparation_version: prepared_payload[:preparation_version],
          page_count: prepared_payload[:page_count]
        }
      )
    end

    def pipeline_context(document, pipeline_run)
      pipeline_run.context.symbolize_keys.merge(
        document_gid: document.to_global_id.to_s,
        pipeline_run_gid: pipeline_run.to_global_id.to_s
      )
    end

    def mark_document_failed(document, error)
      document.reload
      document.document_pages.update_all(status: DocumentPage.statuses.fetch(:failed))

      failure_attributes = {
        status: :failed,
        preparation_status: document.preparation_status == "prepared" ? document.preparation_status : :preparation_failed,
        preparation_error: error.message
      }
      failure_attributes[:summary] = {
        error: {
          class: error.class.name,
          message: error.message
        }
      } unless generated_summary?(document)

      document.update!(failure_attributes)
    end

    def generated_summary?(document)
      document.summary.to_h.with_indifferent_access[:summary].present?
    end
end
