class AppointmentsController < ApplicationController
  include CalendarWorkspace

  before_action :authenticate_user!
  before_action :require_current_account!, only: %i[update destroy]
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

  def update
    @editing_appointment = current_account.appointments.find(params[:id])
    attributes = appointment_params
    if attributes.key?(:dependent_id)
      dependent_id = attributes.delete(:dependent_id)
      attributes[:dependent] = dependent_id.present? ? current_account.dependents.find(dependent_id) : nil
    end

    if @editing_appointment.update(attributes)
      redirect_to calendar_location(month: @editing_appointment.scheduled_at.in_time_zone.strftime("%Y-%m")), notice: "Appointment updated.", status: :see_other
    else
      load_calendar
      render "calendar/show", status: :unprocessable_entity
    end
  end

  def destroy
    current_account.appointments.find(params[:id]).destroy!
    redirect_to calendar_location(month: requested_calendar_month.strftime("%Y-%m")), notice: "Appointment deleted.", status: :see_other
  end

  private

    def appointment_params
      params.require(:appointment).permit(:dependent_id, :scheduled_at, :description)
    end
end
