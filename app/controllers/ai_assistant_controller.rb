class AiAssistantController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dependent_from_param

  def index
    @documents = @dependent.documents.order(created_at: :desc)
    @ai_assistant_query = current_user.ai_assistant_queries.where(
      account: current_account,
      dependent: @dependent
    ).order(created_at: :desc).first
  end

  def create
    ai_assistant_query = current_account.ai_assistant_queries.build(
      dependent: @dependent,
      user: current_user,
      question: params[:q]
    )

    unless ai_assistant_query.save
      redirect_to dependent_ai_assistant_path(@dependent),
        alert: ai_assistant_query.errors.full_messages.to_sentence,
        status: :see_other
      return
    end

    @ai_assistant_query = ai_assistant_query

    respond_to do |format|
      format.turbo_stream
      format.html do
        ai_assistant_query.enqueue_answer!
        redirect_to dependent_ai_assistant_path(@dependent), status: :see_other
      end
    end
  end

  def start
    ai_assistant_query = current_user.ai_assistant_queries.find_by!(
      id: params[:id],
      account: current_account,
      dependent: @dependent
    )
    started = ai_assistant_query.enqueue_answer!

    render json: { started: started }, status: :accepted
  end

  private

    def set_dependent_from_param
      @dependent = current_account.dependents.find(params[:dependent_id])
    end
end
