# frozen_string_literal: true

module Documents
  class ResetProcessing
    def self.call(document, processing_job_id: nil)
      document.with_lock do
        restarting = document.processing? && processing_job_id.present? &&
          document.processing_job_id.to_s == processing_job_id.to_s
        return false if document.processed? || (document.processing? && !restarting)

        # A released Solid Queue job keeps its ID when another worker claims it.
        # Close only that interrupted attempt before rebuilding from the original.
        if restarting
          document.pipeline_runs.where(state: %w[pending processing])
            .where("context->>'processing_job_id' = ?", processing_job_id.to_s).find_each do |run|
              run.mark_failed!(message: "Document processing was interrupted and restarted from the original file.")
            end
        end

        # Image documents use the original upload as their prepared page image.
        # Remove that derived attachment without scheduling its shared blob for purge.
        document.document_pages.includes(image_attachment: :blob).each do |page|
          page.image.detach if page.image.attached? && page.image.blob_id == document.file.blob_id
        end
        document.document_pages.destroy_all
        document.update!(
          status: :processing,
          processing_job_id: processing_job_id,
          preparation_status: :unprepared,
          prepared_payload: {},
          prepared_at: nil,
          preparation_error: nil,
          summary: {},
          summarized_at: nil
        )
      end

      true
    end
  end
end
