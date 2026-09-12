# frozen_string_literal: true

module Documents
  class ResetProcessing
    def self.call(document, processing_job_id: nil)
      document.with_lock do
        return false if document.processing? || document.processed?

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
