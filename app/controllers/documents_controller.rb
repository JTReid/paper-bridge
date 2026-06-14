class DocumentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_document, only: %i[show destroy]

  def index
    @documents = current_account.documents.includes(file_attachment: :blob).order(created_at: :desc)
  end

  def show
  end

  def new
    @document = current_account.documents.new(user: current_user)
  end

  def create
    @document = current_account.documents.new(document_params)
    @document.user = current_user

    if @document.save
      redirect_to @document, notice: "Document uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path, notice: "Document deleted.", status: :see_other
  end

  private

    def current_account
      current_user.account
    end

    def set_document
      @document = current_account.documents.find(params[:id])
    end

    def document_params
      params.require(:document).permit(:title, :description, :file)
    end
end
