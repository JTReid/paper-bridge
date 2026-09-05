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

    if files.empty?
      @document = build_document
      @document.validate
      render :new, status: :unprocessable_entity
      return
    end

    uploaded_documents, failed_uploads = create_uploaded_documents(files)

    if uploaded_documents.empty?
      @document = failed_uploads.first.fetch(:document)
      render :new, status: :unprocessable_entity
    else
      flash[:notice] = upload_success_message(uploaded_documents.count) if uploaded_documents.any?
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

          if document.save
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

    def upload_success_message(count)
      "#{count} #{'document'.pluralize(count)} uploaded and being prepared."
    end

    def upload_failure_message(failed_uploads)
      count = failed_uploads.count
      filenames = failed_uploads.map { |failure| failure.fetch(:filename) }
      visible_filenames = filenames.first(4)
      hidden_count = count - visible_filenames.count
      filename_summary = visible_filenames.to_sentence
      filename_summary = "#{filename_summary}, and #{hidden_count} more" if hidden_count.positive?

      "#{count} #{'file'.pluralize(count)} could not be uploaded: #{filename_summary}."
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
