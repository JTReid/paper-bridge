class ProcessDocumentJob < ApplicationJob
  queue_as :default

  class_attribute :llm_connection, default: RestClient

  retry_on Agentic::Errors::ExecutionError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(document)
    document.processing!

    pipeline_run = create_pipeline_run(document)
    pipeline = Agentic::DocumentSummaryPipeline.new(
      connection: llm_connection,
      context: pipeline_context(document, pipeline_run)
    )

    pipeline.execute

    document.update!(
      status: :processed,
      summary: pipeline.to_response,
      summarized_at: Time.current
    )
  rescue Agentic::Errors::ConfigurationError => e
    mark_document_failed(document, e)
  rescue StandardError => e
    mark_document_failed(document, e)
    raise
  end

  private

    def create_pipeline_run(document)
      PipelineRun.create!(
        subject: document,
        user: document.user,
        context: {
          document_id: document.id,
          account_id: document.account_id,
          filename: document.original_filename,
          content_type: document.content_type,
          byte_size: document.byte_size
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
      document.update!(
        status: :failed,
        summary: {
          error: {
            class: error.class.name,
            message: error.message
          }
        }
      )
    end
end
