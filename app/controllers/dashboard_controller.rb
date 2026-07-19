class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @dependents = current_account.dependents.with_attached_avatar.order(:created_at)
  end
end
