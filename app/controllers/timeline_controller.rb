class TimelineController < ApplicationController
  before_action :authenticate_user!

  def index
    @events = current_user.account.timeline_events
                          .includes(document_chunk: [ :document, :document_page ])
                          .chronological
    @dated_events_by_year = @events.select(&:dated?).group_by { |event| event.sort_date.year }
    @undated_events = @events.reject(&:dated?)
  end
end
