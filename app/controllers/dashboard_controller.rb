class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    return handle_successful_checkout_return if successful_checkout_return?

    @dependents = current_account.dependents.with_attached_avatar.order(:created_at)
    @upcoming_appointments = current_account.appointments
      .where(scheduled_at: Time.current..)
      .includes(:dependent)
      .order(:scheduled_at)
      .limit(5)
  end

  private

    def handle_successful_checkout_return
      if current_account.subscription_active?
        redirect_to dashboard_path, notice: "You’re all set. Your PaperBridge subscription is active."
      elsif current_account.billing_subscription&.checkout_pending?
        render :checkout_pending
      else
        redirect_to billing_path(checkout: "failed")
      end
    end
end
