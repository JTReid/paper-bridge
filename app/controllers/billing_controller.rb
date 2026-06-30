class BillingController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_account!

  def show
    @billing_subscription = current_account.billing_subscription
    @checkout_ready = Billing::StripeConfig.checkout_ready?
    @portal_ready = Billing::StripeConfig.portal_ready?(current_account)
    @can_manage_billing = current_user.can_manage_account?(current_account) || current_user.super_admin?
  end
end
