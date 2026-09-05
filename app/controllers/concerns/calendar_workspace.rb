module CalendarWorkspace
  FAMILY_CALENDAR_FRAME_ID = "family_calendar_frame"

  private

    def set_calendar_context
      context_id = params[:calendar_context_id].presence
      @calendar_context = current_account.dependents.find(context_id) if context_id
    end

    def load_calendar(appointment: nil, month: nil)
      @month = month || requested_calendar_month
      @calendar_start = @month.beginning_of_month.beginning_of_week(:sunday)
      @calendar_end = @month.end_of_month.end_of_week(:sunday)
      @dependents = current_account.dependents.order(:first_name, :last_name)
      @appointments = current_account.appointments
        .includes(:dependent)
        .where(scheduled_at: @calendar_start.beginning_of_day..@calendar_end.end_of_day)
        .order(:scheduled_at)
      @appointments_by_date = @appointments.group_by { |entry| entry.scheduled_at.in_time_zone.to_date }
      @appointment = appointment || Appointment.new(
        dependent: @calendar_context,
        scheduled_at: default_appointment_time
      )
    end

    def requested_calendar_month
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

    def family_calendar_panel_request?
      params[:panel] == "1" || turbo_frame_request_id == FAMILY_CALENDAR_FRAME_ID
    end

    def calendar_location(month:)
      calendar_path(
        month: month,
        calendar_context_id: @calendar_context&.id,
        panel: family_calendar_panel_request? ? 1 : nil
      )
    end
end
