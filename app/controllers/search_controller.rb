class SearchController < ApplicationController
  before_action :authenticate_user!

  class_attribute :llm_connection, default: RestClient

  def index
    @query = params[:q].to_s.strip
    @access_profile = Documents::SearchAccessProfile.for(current_user)
    @results = []
    @search_error = nil

    return if @query.blank?

    pipeline_run = PipelineRun.create!(subject: current_account, user: current_user)
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
    @pipeline_run = pipeline_run
  rescue Agentic::Error => e
    @search_error = e.message
    @results = []
    @answer = nil
  end

  private

    def current_account
      current_user.account
    end

    def pipeline_context(pipeline_run)
      {
        pipeline_run_gid: pipeline_run.to_global_id.to_s,
        account_gid: current_account.to_global_id.to_s,
        actor_gid: current_user.to_global_id.to_s,
        query: @query,
        access_profile: @access_profile,
        limit: 10
      }
    end
end
