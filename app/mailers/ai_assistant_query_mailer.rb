class AiAssistantQueryMailer < ApplicationMailer
  def share
    @query = params.fetch(:query)
    @answer = @query.answer_payload
    @message = params[:message].presence
    @sender_name = @query.user.name.presence || @query.user.email
    @generated_at = @query.completed_at || @query.updated_at
    @citations = Array(@answer[:citations])
    @limitations = Array(@answer[:limitations])

    mail(
      to: params.fetch(:recipient_email),
      reply_to: @query.user.email,
      subject: "PaperBridge: Answer for #{@query.dependent.name}"
    )
  end
end
