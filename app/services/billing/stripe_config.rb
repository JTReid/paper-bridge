module Billing
  class StripeConfig
    INCLUDED_PROFILES = 5
    MAXIMUM_PROFILES = 999_999

    class << self
      def secret_key
        ENV["STRIPE_SECRET_KEY"].presence || credentials[:secret_key].presence
      end

      def publishable_key
        ENV["STRIPE_PUBLISHABLE_KEY"].presence || credentials[:publishable_key].presence
      end

      def webhook_secret
        ENV["STRIPE_WEBHOOK_SECRET"].presence || credentials[:webhook_secret].presence
      end

      def price_id
        ENV["STRIPE_PRICE_ID"].presence ||
          credentials[:standard_price].presence ||
          credentials[:price_id].presence
      end

      def checkout_ready?
        secret_key.present? && profile_price_id.present? && profile_portal_configuration_id.present?
      end

      def profile_price_id
        ENV["STRIPE_PROFILE_PRICE_ID"].presence || credentials[:profile_price].presence
      end

      def profile_portal_configuration_id
        ENV["STRIPE_PROFILE_PORTAL_CONFIGURATION_ID"].presence || credentials[:profile_portal_configuration].presence
      end

      def profile_plan?(subscription)
        subscription.present? && (subscription.profile_limit.present? ||
          (profile_price_id.present? && subscription.stripe_price_id == profile_price_id))
      end

      def portal_ready?(account)
        secret_key.present? && account&.stripe_customer_id.present? &&
          (!profile_plan?(account.billing_subscription) || profile_portal_configuration_id.present?)
      end

      private

        def credentials
          Rails.application.credentials[:stripe] || {}
        end
    end
  end
end
