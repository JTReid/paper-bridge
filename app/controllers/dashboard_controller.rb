class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @dependents = current_account.dependents.order(:created_at)
  end
end
