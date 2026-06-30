module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_super_admin!

    private

      def require_super_admin!
        return if current_user.super_admin?

        redirect_to dashboard_path, alert: "You do not have access to that page."
      end
  end
end
