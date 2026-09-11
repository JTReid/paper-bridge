class MeetingPrepsController < ApplicationController
  include MeetingPrepWorkspace

  before_action :authenticate_user!
  before_action :require_current_account!
  before_action :set_dependent
  before_action :set_meeting_prep, only: %i[show edit update destroy]

  def index
    @meeting_preps = meeting_preps.includes(:meeting_prep_answers).order(updated_at: :desc, id: :desc)
  end

  def new
    @meeting_prep = meeting_preps.new
  end

  def create
    @meeting_prep = meeting_preps.new(meeting_prep_params)
    if @meeting_prep.save
      redirect_to dependent_meeting_prep_path(@dependent, @meeting_prep), notice: "Meeting created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    load_meeting_prep_workspace
  end

  def edit
  end

  def update
    if @meeting_prep.update(meeting_prep_params)
      redirect_to dependent_meeting_prep_path(@dependent, @meeting_prep), notice: "Meeting updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @meeting_prep.destroy!
    redirect_to dependent_meeting_preps_path(@dependent), notice: "Meeting deleted. Your saved answers are still available.", status: :see_other
  end

  private

    def set_dependent
      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def meeting_preps
      current_user.meeting_preps.where(account: current_account, dependent: @dependent)
    end

    def set_meeting_prep
      @meeting_prep = meeting_preps.find(params[:id])
    end

    def meeting_prep_params
      params.require(:meeting_prep).permit(:name)
    end
end
