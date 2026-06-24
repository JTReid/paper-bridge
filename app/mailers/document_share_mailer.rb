class DocumentShareMailer < ApplicationMailer
  def share
    @share_event = params.fetch(:share_event)
    @documents = shared_documents

    attach_documents

    mail(
      to: @share_event.recipient_email,
      subject: @share_event.subject.presence || default_subject
    )
  end

  private

    def shared_documents
      return Array(params[:documents]) if params.key?(:documents)

      @share_event.documents.with_attached_file.order(:created_at)
    end

    def default_subject
      count = @documents.count
      "PaperBridge: #{count} #{'document'.pluralize(count)} shared"
    end

    def attach_documents
      used_filenames = Hash.new(0)

      @documents.each do |document|
        next unless document.file.attached?

        filename = unique_attachment_filename(attachment_filename(document), used_filenames)
        attachments[filename] = {
          mime_type: document.content_type.presence || "application/octet-stream",
          content: document.file.download
        }
      end
    end

    def attachment_filename(document)
      document.original_filename.presence || document.file.filename.to_s
    end

    def unique_attachment_filename(filename, used_filenames)
      used_filenames[filename] += 1
      return filename if used_filenames[filename] == 1

      extension = File.extname(filename)
      basename = File.basename(filename, extension)
      "#{basename}-#{used_filenames[filename]}#{extension}"
    end
end
