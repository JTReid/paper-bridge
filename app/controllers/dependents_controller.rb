class DependentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dependent, only: %i[show edit update destroy]

  def index
    @dependents = current_account.dependents.order(:created_at)
    @documents = current_account.documents.order(created_at: :desc).to_a
  end

  def show
    @documents = @dependent.documents.includes(:document_chunks).order(created_at: :desc).to_a
    @care_team_memberships = @dependent.care_team_memberships.includes(:user).order(:created_at)
  end

  def new
    @dependent = current_account.dependents.new
  end

  def create
    @dependent = current_account.dependents.new(dependent_params)

    if @dependent.save
      redirect_to @dependent, notice: "Dependent created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @dependent.update(dependent_params)
      redirect_to @dependent, notice: "Dependent updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @dependent.destroy
      redirect_to dependents_path, notice: "Dependent deleted.", status: :see_other
    else
      redirect_to @dependent, alert: @dependent.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

    def set_dependent
      @dependent = current_account.dependents.find(params[:id])
    end

    def dependent_params
      params.require(:dependent).permit(:name, :date_of_birth, :avatar_url, :grade, :school, :notes)
    end
end
