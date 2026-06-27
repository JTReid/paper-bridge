class ShareEventsController < ApplicationController
  MAX_ATTACHMENT_BYTES = 20.megabytes

  before_action :authenticate_user!

  def create
    documents = selected_documents
    share_event = build_share_event

    if documents.empty?
      redirect_back fallback_location: documents_path_fallback, alert: "Choose at least one document to share."
      return
    end

    if total_attachment_bytes(documents) > MAX_ATTACHMENT_BYTES
      redirect_back fallback_location: documents_path_fallback, alert: "Selected files are too large to send by email."
      return
    end

    share_event.save!
    share_event.documents = documents

    DocumentShareMailer.with(share_event: share_event).share.deliver_now
    share_event.mark_sent!

    redirect_back fallback_location: documents_path_fallback, notice: "Documents shared with #{share_event.recipient_email}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: documents_path_fallback, alert: e.record.errors.full_messages.to_sentence
  rescue StandardError => e
    share_event&.mark_failed!(e) if share_event&.persisted?
    log_share_delivery_failure(e, share_event)
    redirect_back fallback_location: documents_path_fallback, alert: "Documents could not be shared."
  end

  private

    def share_event_params
      params.require(:share_event).permit(:recipient_email, :subject, :message, document_ids: [])
    end

    def selected_documents
      ids = Array(share_event_params[:document_ids]).compact_blank.uniq

      current_account.documents.with_attached_file.where(id: ids).order(:created_at).to_a
    end

    def build_share_event
      current_account.share_events.new(
        sender: current_user,
        recipient_email: share_event_params[:recipient_email],
        subject: share_event_params[:subject],
        message: share_event_params[:message],
        status: :pending
      )
    end

    def total_attachment_bytes(documents)
      documents.sum { |document| document.file.attached? ? document.file.blob.byte_size : 0 }
    end

    def documents_path_fallback
      dependent = current_account.dependents.find_by(id: params[:dependent_id])
      dependent ? dependent_documents_path(dependent) : dashboard_path
    end

    def log_share_delivery_failure(error, share_event)
      logger.error(
        [
          "document_share_delivery_failed",
          "share_event_id=#{share_event&.id || "none"}",
          "account_id=#{current_account&.id || "none"}",
          "error_class=#{error.class.name}",
          "error_message=#{error.message.to_s.squish}"
        ].join(" ")
      )
    end
end
