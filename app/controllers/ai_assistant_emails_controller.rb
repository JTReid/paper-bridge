class AiAssistantEmailsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_account!
  before_action :set_query
  before_action :expires_now

  def new
    set_recipient_options
  end

  def create
    raw_email = email_params[:recipient_email].to_s
    @recipient_email = raw_email.strip
    @message = email_params[:message].to_s.strip

    @error = if @recipient_email.blank?
      "Enter an email address."
    elsif !@recipient_email.match?(URI::MailTo::EMAIL_REGEXP) || raw_email.match?(/[,;<>\r\n]/)
      "Enter a valid email address."
    end

    if @error.nil? && !deliver_email
      @error = "Answer could not be emailed. Please try again."
    end

    if @error
      set_recipient_options
      render :new, status: :unprocessable_entity
    else
      render :create
    end
  end

  private

    def set_query
      @dependent = current_account.dependents.find(params[:dependent_id])
      @query = current_user.ai_assistant_queries.where(account: current_account, dependent: @dependent).find(params[:id])

      unless @query.completed? && @query.answer.is_a?(Hash) && @query.answer["answer"].is_a?(String) && @query.answer["answer"].present?
        raise ActiveRecord::RecordNotFound
      end
    end

    def email_params
      params.require(:ai_assistant_email).permit(:recipient_email, :message)
    end

    def set_recipient_options
      @recipient_options = @dependent.care_team_memberships.order(:name).map do |contact|
        [ "#{contact.name} (#{contact.email})", contact.email ]
      end
    end

    def deliver_email
      AiAssistantQueryMailer.with(query: @query, recipient_email: @recipient_email, message: @message).share.deliver_now
      true
    rescue StandardError => error
      logger.error("ai_assistant_email_delivery_failed query_id=#{@query.id} account_id=#{current_account.id} error_class=#{error.class.name}")
      false
    end
end
