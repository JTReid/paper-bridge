class AppointmentsController < ApplicationController
  before_action :authenticate_user!

  def create
    dependent = current_account.dependents.find(appointment_params[:dependent_id])
    @appointment = dependent.appointments.new(appointment_params.except(:dependent_id))

    if @appointment.save
      redirect_to calendar_path(month: @appointment.scheduled_at.strftime("%Y-%m")), notice: "Appointment added."
    else
      load_calendar
      render "calendar/show", status: :unprocessable_entity
    end
  end

  private

    def appointment_params
      params.require(:appointment).permit(:dependent_id, :scheduled_at, :description)
    end

    def load_calendar
      @month = (@appointment.scheduled_at&.to_date || requested_month).beginning_of_month
      @calendar_start = @month.beginning_of_month.beginning_of_week(:sunday)
      @calendar_end = @month.end_of_month.end_of_week(:sunday)
      @dependents = current_account.dependents.order(:name)
      @appointments = current_account.appointments
        .includes(:dependent)
        .where(scheduled_at: @calendar_start.beginning_of_day..@calendar_end.end_of_day)
        .order(:scheduled_at)
      @appointments_by_date = @appointments.group_by { |entry| entry.scheduled_at.in_time_zone.to_date }
    end

    def requested_month
      month_param = params[:month].to_s
      return Date.current unless month_param.match?(/\A\d{4}-(?:0[1-9]|1[0-2])\z/)

      Date.strptime(month_param, "%Y-%m")
    rescue Date::Error
      Date.current
    end
end
