class CalendarController < ApplicationController
  before_action :authenticate_user!

  def show
    load_calendar
  end

  private

    def load_calendar(appointment: nil, month: nil)
      @month = month || requested_month
      @calendar_start = @month.beginning_of_month.beginning_of_week(:sunday)
      @calendar_end = @month.end_of_month.end_of_week(:sunday)
      @dependents = current_account.dependents.order(:name)
      @appointments = current_account.appointments
        .includes(:dependent)
        .where(scheduled_at: @calendar_start.beginning_of_day..@calendar_end.end_of_day)
        .order(:scheduled_at)
      @appointments_by_date = @appointments.group_by { |entry| entry.scheduled_at.in_time_zone.to_date }
      @appointment = appointment || Appointment.new(scheduled_at: default_appointment_time)
    end

    def requested_month
      month_param = params[:month].to_s
      return Date.current.beginning_of_month unless month_param.match?(/\A\d{4}-(?:0[1-9]|1[0-2])\z/)

      Date.strptime(month_param, "%Y-%m").beginning_of_month
    rescue Date::Error
      Date.current.beginning_of_month
    end

    def default_appointment_time
      return 1.hour.from_now.change(min: 0) if @month == Date.current.beginning_of_month

      @month.in_time_zone.change(hour: 9)
    end
end
