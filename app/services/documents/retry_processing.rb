# frozen_string_literal: true

module Documents
  class RetryProcessing
    class EnqueueError < StandardError; end

    def self.call(document)
      new(document).call
    end

    def initialize(document)
      @document = document
    end

    def call
      document.with_lock do
        return false unless document.failed? && document.processable? && document.file.attached?
        return false if pending_job?

        document.queued!
        job = job_class.perform_later(document)
        raise EnqueueError, "Document processing could not be queued" unless job && job.successfully_enqueued?
      end

      true
    rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
      Rails.logger.warn("document_retry_enqueue_failed document_id=#{document.id} error_class=#{error.class.name}")
      raise EnqueueError, "Document processing could not be queued"
    end

    private

      attr_reader :document

      def job_class
        document.content_type.start_with?("image/") ? ProcessImageDocumentJob : ProcessDocumentJob
      end

      def pending_job?
        return false unless job_class.queue_adapter_name == "solid_queue"

        # A failed document can still have an automatic retry waiting in the queue.
        SolidQueue::Job.where(class_name: %w[ProcessDocumentJob ProcessImageDocumentJob], finished_at: nil)
          .where("arguments::jsonb -> 'arguments' -> 0 ->> '_aj_globalid' = ?", document.to_global_id.to_s)
          .where.not(id: SolidQueue::FailedExecution.select(:job_id)).exists?
      end
  end
end
