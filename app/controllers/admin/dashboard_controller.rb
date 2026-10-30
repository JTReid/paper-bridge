module Admin
  class DashboardController < BaseController
    def show
      @stats = AdminDashboard::Stats.new
    end
  end
end
