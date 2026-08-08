class AppointmentsController < ApplicationController
  include CalendarWorkspace

  before_action :authenticate_user!
  before_action :set_calendar_context

  def create
    dependent = current_account.dependents.find(appointment_params[:dependent_id])
    @appointment = dependent.appointments.new(appointment_params.except(:dependent_id))

    if @appointment.save
      redirect_to calendar_location(month: @appointment.scheduled_at.in_time_zone.strftime("%Y-%m")), notice: "Appointment added.", status: :see_other
    else
      appointment_month = @appointment.scheduled_at&.in_time_zone&.to_date&.beginning_of_month
      load_calendar(appointment: @appointment, month: appointment_month)
      render "calendar/show", status: :unprocessable_entity
    end
  end

  private

    def appointment_params
      params.require(:appointment).permit(:dependent_id, :scheduled_at, :description)
    end
end
