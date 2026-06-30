module Billing
  class StripeConfig
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
        secret_key.present? && price_id.present?
      end

      def portal_ready?(account)
        secret_key.present? && account&.stripe_customer_id.present?
      end

      private

        def credentials
          Rails.application.credentials[:stripe] || {}
        end
    end
  end
end
