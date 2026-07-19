class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @dependents = current_account.dependents.with_attached_avatar.order(:created_at)
    @upcoming_appointments = current_account.appointments
      .where(scheduled_at: Time.current..)
      .includes(:dependent)
      .order(:scheduled_at)
      .limit(5)
  end
end
