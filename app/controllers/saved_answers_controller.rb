class SavedAnswersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_account!
  before_action :set_dependent
  before_action :set_saved_answer, only: %i[show edit update destroy add_to_meeting]
  before_action :set_meeting_preps, only: %i[index show edit update]

  def index
    @query = params[:q].to_s.strip
    @saved_answers = saved_answers.search(@query).order(created_at: :desc, id: :desc)
    if params[:meeting_prep_id].present?
      @meeting_prep = meeting_preps.find(params[:meeting_prep_id])
      @saved_answers = @saved_answers.joins(:meeting_prep_answers)
        .where(meeting_prep_answers: { meeting_prep_id: @meeting_prep.id })
    end
  end

  def show
  end

  def edit
  end

  def create
    query = current_user.ai_assistant_queries.where(account: current_account, dependent: @dependent)
      .find(params[:ai_assistant_query_id])
    saved_answer = SavedAnswer.save_from_query!(query)
    redirect_to dependent_saved_answer_path(@dependent, saved_answer), notice: "Answer saved.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dependent_ai_assistant_path(@dependent), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  def update
    if @saved_answer.update(params.require(:saved_answer).permit(:title, :notes))
      redirect_to dependent_saved_answer_path(@dependent, @saved_answer), notice: "Saved answer updated.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @saved_answer.destroy!
    redirect_to dependent_saved_answers_path(@dependent), notice: "Saved answer deleted.", status: :see_other
  end

  def add_to_meeting
    meeting_prep = meeting_preps.find(params[:meeting_prep_id])
    meeting_prep.add_answer!(@saved_answer)
    redirect_to dependent_meeting_prep_path(@dependent, meeting_prep), notice: "Answer added to meeting.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to dependent_saved_answer_path(@dependent, @saved_answer), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  private

    def set_dependent
      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def saved_answers
      current_user.saved_answers.where(account: current_account, dependent: @dependent)
    end

    def meeting_preps
      current_user.meeting_preps.where(account: current_account, dependent: @dependent)
    end

    def set_saved_answer
      @saved_answer = saved_answers.find(params[:id])
    end

    def set_meeting_preps
      @meeting_preps = meeting_preps.order(:name, :id)
    end
end
