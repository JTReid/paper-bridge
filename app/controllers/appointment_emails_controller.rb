class AppointmentEmailsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_appointment

  def create
    if recipient_email.blank?
      redirect_to_calendar alert: "Enter an email address."
      return
    end

    unless recipient_email.match?(URI::MailTo::EMAIL_REGEXP)
      redirect_to_calendar alert: "Enter a valid email address."
      return
    end

    AppointmentMailer.with(appointment: @appointment, recipient_email: recipient_email).share.deliver_now

    redirect_to_calendar notice: "Appointment emailed to #{recipient_email}."
  rescue StandardError => error
    log_delivery_failure(error)
    redirect_to_calendar alert: "Appointment could not be emailed."
  end

  private

    def set_appointment
      @appointment = current_account.appointments.find(appointment_email_params[:appointment_id])
    end

    def appointment_email_params
      params.require(:appointment_email).permit(:appointment_id, :recipient_email)
    end

    def recipient_email
      @recipient_email ||= appointment_email_params[:recipient_email].to_s.strip
    end

    def redirect_to_calendar(**flash)
      redirect_to calendar_path(month: @appointment.scheduled_at.in_time_zone.strftime("%Y-%m")), **flash
    end

    def log_delivery_failure(error)
      logger.error(
        [
          "appointment_email_delivery_failed",
          "appointment_id=#{@appointment.id}",
          "account_id=#{current_account.id}",
          "error_class=#{error.class.name}",
          "error_message=#{error.message.to_s.squish}"
        ].join(" ")
      )
    end
end
