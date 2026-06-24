class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dependent_from_param
  before_action :set_document, only: %i[show edit update destroy]

  def index
    scope = @dependent ? @dependent.documents : current_account.documents
    @documents = scope.includes(:dependent, :document_chunks, file_attachment: :blob).order(created_at: :desc).to_a
    @processed_count = @documents.count(&:processed?)
    @processing_count = @documents.count { |document| document.queued? || document.processing? }
  end

  def show
  end

  def edit
  end

  def new
    set_form_options

    @document = current_account.documents.new(user: current_user, dependent: @dependent, category: :general)
  end

  def create
    set_form_options
    @document = current_account.documents.new(document_params)
    @document.user = current_user
    @document.dependent = @dependent

    if @document.save
      redirect_to @document, notice: "Document uploaded."
    else
      render :new, status: :unprocessable_entity
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
      @dependents = current_account.dependents.order(:name)
    end

    def set_document
      @document = current_account.documents.find(params[:id])
      @dependent ||= @document.dependent
    end

    def document_params
      params.require(:document).permit(:title, :description, :category, :file)
    end

    def document_update_params
      params.require(:document).permit(:title, :description, :category)
    end
end
