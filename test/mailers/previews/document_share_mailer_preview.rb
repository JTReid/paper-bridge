class DocumentShareMailerPreview < ActionMailer::Preview
  def share
    share_event = latest_share_event || preview_share_event
    params = { share_event: share_event }
    params[:documents] = preview_documents unless share_event.persisted?

    DocumentShareMailer.with(**params).share
  end

  private

    PreviewDocument = Struct.new(:title, :category, :summary) do
      def file
        PreviewAttachment.new
      end
    end

    PreviewAttachment = Struct.new do
      def attached?
        false
      end
    end

    def latest_share_event
      ShareEvent.includes(:sender, documents: { file_attachment: :blob }).order(created_at: :desc).first
    end

    def preview_share_event
      ShareEvent.new(
        account: preview_account,
        sender: preview_sender,
        recipient_email: "recipient@example.test",
        subject: "Shared PaperBridge documents",
        message: "Hi, I attached the documents we discussed."
      )
    end

    def preview_documents
      documents = Document.with_attached_file.order(created_at: :desc).limit(3).to_a
      return documents if documents.any?

      [
        PreviewDocument.new(
          "Sample Care Plan",
          "general",
          { "summary" => "A short summary of the selected document appears here when one is available." }
        )
      ]
    end

    def preview_account
      preview_sender.account || Account.order(:created_at).first
    end

    def preview_sender
      @preview_sender ||= User.order(:created_at).first || User.new(name: "PaperBridge User", email: "sender@example.test")
    end
end
