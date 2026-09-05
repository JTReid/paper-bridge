class DocumentsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_dependent_from_param
  before_action :set_document, only: %i[show edit update destroy original]

  def index
    scope = @dependent ? @dependent.documents : current_account.documents
    @query = params[:q].to_s.strip.presence
    @category = params[:category] if Document.categories.key?(params[:category])
    scope = scope.search_by_filename(@query) if @query
    scope = scope.where(category: @category) if @category
    @documents = scope.includes(:dependent, file_attachment: :blob).order(created_at: :desc).to_a
    @processed_count = @documents.count(&:processed?)
    @processing_count = @documents.count { |document| document.queued? || document.processing? }
    @share_recipient_options = share_recipient_options
  end

  def show
  end

  def original
    return head :not_found unless @document.file.attached?

    disposition = @document.content_type == "application/pdf" ? "inline" : "attachment"
    storage_url = @document.file.url(disposition: disposition, expires_in: 5.minutes)
    page_number = positive_page_number
    storage_url = "#{storage_url}#page=#{page_number}" if disposition == "inline" && page_number

    redirect_to storage_url, allow_other_host: true
  end

  def edit
  end

  def new
    set_form_options

    @document = build_document
  end

  def create
    set_form_options
    upload_params = document_upload_params
    files = uploaded_files(upload_params)

    if files.size > Document::MAX_UPLOAD_FILES
      @document = build_document
      @document.errors.add(:base, "You can upload up to #{Document::MAX_UPLOAD_FILES} files at a time. No files were uploaded. Please select fewer files.")
      render :new, status: :unprocessable_entity
      return
    end

    if files.empty?
      @document = build_document
      @document.validate
      render :new, status: :unprocessable_entity
      return
    end

    uploaded_documents, failed_uploads = create_uploaded_documents(files)

    if uploaded_documents.empty?
      @document = failed_uploads.first.fetch(:document)
      flash.now[:alert] = upload_failure_message(failed_uploads)
      render :new, status: :unprocessable_entity
    else
      flash[:notice] = upload_success_message(uploaded_documents)
      flash[:alert] = upload_failure_message(failed_uploads) if failed_uploads.any?
      redirect_to dependent_documents_path(@dependent)
    end
  end

  def update
    if @document.update(document_update_params)
      redirect_to @document, notice: "Document updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    dependent = @document.dependent

    @document.destroy
    redirect_to dependent_documents_path(dependent), notice: "Document deleted.", status: :see_other
  end

  private

    def set_dependent_from_param
      return if params[:dependent_id].blank?

      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def set_form_options
      @dependents = current_account.dependents.order(:first_name, :last_name)
    end

    def set_document
      @document = current_account.documents.find(params[:id])
      @dependent ||= @document.dependent
    end

    def document_upload_params
      params.require(:document).permit(:file, files: [])
    end

    def positive_page_number
      page_number = Integer(params[:page], exception: false)
      page_number if page_number&.positive?
    end

    def document_update_params
      params.require(:document).permit(:title, :description, :category)
    end

    def uploaded_files(upload_params)
      files = upload_params[:files].presence || upload_params[:file]

      Array.wrap(files).reject(&:blank?)
    end

    def create_uploaded_documents(files)
      uploaded_documents = []
      failed_uploads = []

      files.each do |file|
        document = build_document
        normalized_upload = nil

        begin
          normalized_upload = Documents::UploadNormalizer.call(file)
          document.file.attach(normalized_upload.attachable)

          if save_unique_upload(document)
            uploaded_documents << document
          else
            failed_uploads << failed_upload_for(file, document)
          end
        rescue Documents::UploadNormalizer::Error => error
          Rails.logger.warn("document_upload_rejected error_class=#{error.class.name} error_message=#{error.message.to_s.squish}")
          document.errors.add(:file, error.message)
          failed_uploads << failed_upload_for(file, document)
        rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError => error
          Rails.logger.warn("document_upload_rejected error_class=#{error.class.name} error_message=#{error.message.to_s.squish}")
          document.errors.add(:file, "could not be attached. Please choose the file again.")
          failed_uploads << failed_upload_for(file, document)
        ensure
          normalized_upload&.close
        end
      end

      [ uploaded_documents, failed_uploads ]
    end

    def save_unique_upload(document)
      # Serialize uploads for one profile so concurrent requests cannot both
      # pass the duplicate check before either attachment is committed.
      @dependent.with_lock do
        blob = document.file.blob
        duplicate = @dependent.documents.joins(file_attachment: :blob)
          .where(active_storage_blobs: { checksum: blob.checksum, byte_size: blob.byte_size }).exists?

        if duplicate
          document.errors.add(:file, "is already saved in this profile. Duplicate files are not uploaded.")
          false
        else
          document.save
        end
      end
    end

    def build_document
      current_account.documents.new(
        user: current_user,
        dependent: @dependent,
        category: :general,
        initial_metadata_pending: true
      )
    end

    def failed_upload_for(file, document)
      {
        document: document,
        filename: upload_filename(file),
        errors: document.errors.full_messages
      }
    end

    def upload_filename(file)
      return file.original_filename.to_s if file.respond_to?(:original_filename) && file.original_filename.present?

      "Unnamed file"
    end

    def upload_success_message(documents)
      stored_count = documents.count(&:stored?)
      processing_count = documents.size - stored_count

      [
        ("#{processing_count} #{'document'.pluralize(processing_count)} uploaded and being prepared." if processing_count.positive?),
        ("#{stored_count} #{'document'.pluralize(stored_count)} saved without processing." if stored_count.positive?)
      ].compact.join(" ")
    end

    def upload_failure_message(failed_uploads)
      count = failed_uploads.count
      details = failed_uploads.first(4).map do |failure|
        "#{failure.fetch(:filename)}: #{failure.fetch(:errors).to_sentence}"
      end
      hidden_count = count - details.size
      details << "and #{hidden_count} more" if hidden_count.positive?

      "#{count} #{'file'.pluralize(count)} could not be uploaded. #{details.join('; ')}"
    end

    def share_recipient_options
      scope = @dependent ? @dependent.care_team_memberships : current_account.care_team_memberships

      scope.order(:name).filter_map do |membership|
        email = membership.email.to_s.strip
        next if email.blank?

        name = membership.name.presence || membership.role.humanize
        [ "#{name} (#{email})", email ]
      end.uniq { |_label, email| email.downcase }
    end
end
