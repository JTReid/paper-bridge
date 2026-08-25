module Billing
  class CheckoutReturnBroadcaster
    class << self
      def call(subscription)
        Turbo::StreamsChannel.broadcast_refresh_to(subscription.account, :billing_checkout)
      rescue StandardError => e
        Rails.logger.warn(
          "stripe_checkout_return_broadcast_failed " \
          "account_id=#{subscription.account_id} " \
          "billing_subscription_id=#{subscription.id} " \
          "error_class=#{e.class.name}"
        )
      end
    end
  end
end
