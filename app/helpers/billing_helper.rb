module BillingHelper
  def profile_subscription_monthly_price(subscription)
    return unless Billing::StripeConfig.profile_plan?(subscription) && subscription.profile_limit.present?

    amount = 25 + 5 * (subscription.profile_limit - BillingSubscription::INCLUDED_PROFILES)
    "#{number_to_currency(amount, precision: 0)} USD/month"
  end
end
