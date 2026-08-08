class CalendarController < ApplicationController
  include CalendarWorkspace

  before_action :authenticate_user!
  before_action :set_calendar_context

  def show
    load_calendar
  end
end
