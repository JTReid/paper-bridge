class MeetingPrepAnswersController < ApplicationController
  include MeetingPrepWorkspace

  before_action :authenticate_user!
  before_action :require_current_account!
  before_action :set_dependent
  before_action :set_meeting_prep

  def create
    saved_answers = current_user.saved_answers.where(account: current_account, dependent: @dependent)
      .find(requested_saved_answer_ids)
    entries = @meeting_prep.add_answers!(saved_answers)
    message = entries.one? ? "Answer added to meeting." : "#{entries.size} answers added to meeting."
    respond_with_workspace(notice: message)
  rescue ActiveRecord::RecordInvalid => error
    respond_invalid(error)
  end

  def update
    @meeting_prep.meeting_prep_answers.find(params[:id]).move!(params[:direction])
    respond_with_workspace(notice: "Answer moved.")
  rescue ActiveRecord::RecordInvalid => error
    respond_invalid(error)
  end

  def destroy
    @meeting_prep.meeting_prep_answers.find(params[:id]).destroy!
    respond_with_workspace(notice: "Answer removed from meeting. It is still in your saved answers.")
  end

  private

    def set_dependent
      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def set_meeting_prep
      @meeting_prep = current_user.meeting_preps.where(account: current_account, dependent: @dependent)
        .find(params[:meeting_prep_id])
    end

    def requested_saved_answer_ids
      permitted = params.permit(:saved_answer_id, saved_answer_ids: [])
      value = params.key?(:saved_answer_ids) ? permitted[:saved_answer_ids] : permitted[:saved_answer_id]
      Array(value).compact_blank.uniq
    end

    def respond_invalid(error)
      respond_with_workspace(alert: error.record.errors.full_messages.to_sentence, status: :unprocessable_entity)
    end

    def respond_with_workspace(notice: nil, alert: nil, status: :ok)
      respond_to do |format|
        format.turbo_stream do
          @notice = notice
          @alert = alert
          load_meeting_prep_workspace
          render turbo_stream: turbo_stream.update(
            ActionView::RecordIdentifier.dom_id(@meeting_prep, :workspace),
            partial: "meeting_preps/workspace"
          ), status: status
        end
        format.html do
          redirect_to dependent_meeting_prep_path(@dependent, @meeting_prep), notice: notice, alert: alert, status: :see_other
        end
      end
    end
end
