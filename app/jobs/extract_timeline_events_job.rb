# frozen_string_literal: true

class ExtractTimelineEventsJob < ApplicationJob
  queue_as :default
  # Follow-up work: smaller Solid Queue priorities run first, so user-facing
  # jobs such as Ask PaperBridge answers go ahead of timeline extraction.
  queue_with_priority 10

  class_attribute :llm_connection, default: RestClient

  retry_on Agentic::Errors::ExecutionError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(document)
    return unless document.processed?
    return if Agents::TimelineEventExtractor.skip?(document)

    pipeline_run = PipelineRun.create!(
      subject: document,
      user: document.user,
      context: {
        document_id: document.id,
        account_id: document.account_id,
        filename: document.original_filename,
        content_type: document.content_type
      }
    )

    Agentic::TimelineExtractionPipeline.new(
      connection: llm_connection,
      context: pipeline_run.context.symbolize_keys.merge(
        document_gid: document.to_global_id.to_s,
        pipeline_run_gid: pipeline_run.to_global_id.to_s
      )
    ).execute
  rescue StandardError
    raise if Document.exists?(document.id)

    # The document was deleted mid-run and its chunks went with it, so there is
    # nothing left to extract. Also remove a run created after the delete.
    pipeline_run&.destroy
  end
end
