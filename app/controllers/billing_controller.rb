class BillingController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_account!

  def show
    case params[:checkout]
    when "cancel"
      clear_checkout_pending
      redirect_to billing_path, notice: "Checkout canceled. Your subscription hasn’t changed."
      return
    when "failed"
      redirect_to billing_path, alert: "Your subscription isn’t active yet. Review your billing details and try again."
      return
    end

    @billing_subscription = current_account.billing_subscription
    @checkout_ready = Billing::StripeConfig.checkout_ready?
    @portal_ready = Billing::StripeConfig.portal_ready?(current_account)
    @can_manage_billing = current_user.can_manage_account?(current_account) || current_user.super_admin?
    @launch_trial_available = (@billing_subscription || BillingSubscription.new(account: current_account)).launch_trial_available?
  end

  private

    def clear_checkout_pending
      subscription = current_account.billing_subscription
      return unless subscription&.checkout_pending?

      subscription.clear_checkout_pending
      subscription.save!
    end
end
