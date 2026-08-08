class AiAssistantController < ApplicationController
  before_action :authenticate_user!

  class_attribute :llm_connection, default: RestClient

  def index
    set_dependent_from_param
    @query = params[:q].to_s.strip
    @access_profile = Documents::SearchAccessProfile.for(current_user, account: current_account, dependent: @dependent)
    @documents = (@dependent ? @dependent.documents : current_account.documents).order(created_at: :desc)
    @results = []
    @source_documents_by_id = {}
    @search_error = nil

    return if @query.blank?

    pipeline_run = PipelineRun.create!(
      subject: current_account,
      user: current_user,
      context: { query: @query }
    )
    pipeline = Agentic::DocumentSearchPipeline.new(
      context: pipeline_context(pipeline_run),
      connection: llm_connection,
      synthesize_answer: true
    )

    pipeline.execute
    response = pipeline.to_response

    @results = response[:results]
    @result_count = response[:result_count]
    @answer = response[:answer]
    @source_documents_by_id = @results.to_h { |result| [ result.document.id, result.document ] }
  rescue Agentic::Errors::Error => e
    Rails.logger.error("paperbridge_answer_failed error_class=#{e.class.name} error_message=#{e.message.to_s.squish}")
    @search_error = "We couldn’t answer that right now. Please try again in a moment."
    @results = []
    @source_documents_by_id = {}
    @answer = nil
  end

  private

    def set_dependent_from_param
      return if params[:dependent_id].blank?

      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def pipeline_context(pipeline_run)
      {
        pipeline_run_gid: pipeline_run.to_global_id.to_s,
        account_gid: current_account.to_global_id.to_s,
        actor_gid: current_user.to_global_id.to_s,
        dependent_gid: @dependent&.to_global_id&.to_s,
        query: @query,
        access_profile: @access_profile,
        limit: 10
      }
    end
end
