class AppointmentMailer < ApplicationMailer
  CENTRAL_TIME_ZONE = "Central Time (US & Canada)"

  def share
    @appointment = params.fetch(:appointment)
    @recipient_email = params.fetch(:recipient_email)
    @scheduled_at = @appointment.scheduled_at.in_time_zone(CENTRAL_TIME_ZONE)

    mail(
      to: @recipient_email,
      subject: "PaperBridge: Appointment for #{@appointment.dependent.name}"
    )
  end
end
