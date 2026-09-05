module Billing
  # Explicit, test-mode-only setup. Never updates prices, portal configurations,
  # customers, or subscriptions that already exist.
  class ProfilePlanSetup
    class ConfigurationError < StandardError; end

    VERSION = "paperbridge_managed_profiles_monthly_v1"

    def initialize(api_key: StripeConfig.secret_key)
      @api_key = api_key
    end

    def call(confirm_test_mode: false)
      unless confirm_test_mode && @api_key.to_s.match?(/\A(?:rk|sk)_test_\S+\z/)
        raise ConfigurationError, "Setup requires explicit confirmation and a Stripe test-mode key. Live keys are never accepted."
      end

      price = find_or_create_price
      validate_price!(price)
      portal = find_or_create_portal(price)
      validate_portal!(portal, price)

      { price_id: price.id, product_id: price.product, portal_configuration_id: portal.id }
    end

    private

      def find_or_create_price
        prices = Stripe::Price.list({ lookup_keys: [ VERSION ], limit: 2, expand: [ "data.tiers" ] }, request_options)
        raise ConfigurationError, "More than one profile price matched; review the test catalog." if prices.data.size > 1

        prices.data.first || Stripe::Price.create({
          currency: "usd",
          billing_scheme: "tiered",
          tiers_mode: "graduated",
          recurring: { interval: "month", interval_count: 1, usage_type: "licensed" },
          tiers: [
            { up_to: StripeConfig::INCLUDED_PROFILES, unit_amount: 0, flat_amount: 2500 },
            { up_to: "inf", unit_amount: 500, flat_amount: 0 }
          ],
          # Explicit tax behavior is required for Customer Portal updates. This
          # does not enable automatic tax collection or change existing taxes.
          tax_behavior: "exclusive",
          product_data: { name: "PaperBridge managed profiles", unit_label: "profile" },
          lookup_key: VERSION,
          metadata: { paperbridge_plan: VERSION },
          expand: [ "tiers" ]
        }, request_options(idempotency_key: "#{VERSION}_price"))
      end

      def find_or_create_portal(price)
        configurations = Stripe::BillingPortal::Configuration.list({
          limit: 100, expand: [ "data.features.subscription_update.products" ]
        }, request_options)
        existing = configurations.auto_paging_each.find do |configuration|
          configuration.metadata["paperbridge_plan"] == VERSION && configuration.metadata["price_id"] == price.id
        end

        existing || Stripe::BillingPortal::Configuration.create({
          name: "PaperBridge managed profiles",
          features: portal_features(price),
          metadata: { paperbridge_plan: VERSION, price_id: price.id },
          expand: [ "features.subscription_update.products" ]
        }, request_options(idempotency_key: "#{VERSION}_portal_#{price.id}"))
      end

      def portal_features(price)
        {
          customer_update: { enabled: true, allowed_updates: [ "email", "name", "address" ] },
          payment_method_update: { enabled: true },
          invoice_history: { enabled: true },
          subscription_cancel: { enabled: true, mode: "at_period_end" },
          subscription_update: {
            enabled: true,
            default_allowed_updates: [ "quantity" ],
            products: [ {
              product: price.product,
              prices: [ price.id ],
              adjustable_quantity: {
                enabled: true, minimum: StripeConfig::INCLUDED_PROFILES, maximum: StripeConfig::MAXIMUM_PROFILES
              }
            } ],
            proration_behavior: "always_invoice",
            schedule_at_period_end: { conditions: [ { type: "decreasing_item_amount" } ] }
          }
        }
      end

      def validate_price!(price)
        tiers = price.to_hash[:tiers].to_a
        valid = price.livemode == false && price.active && price.currency == "usd" &&
          price.billing_scheme == "tiered" && price.tiers_mode == "graduated" && price.tax_behavior == "exclusive" &&
          price.recurring.interval == "month" && price.recurring.interval_count == 1 && price.recurring.usage_type == "licensed" &&
          tiers.size == 2 && tiers[0].slice(:up_to, :unit_amount, :flat_amount) == { up_to: 5, unit_amount: 0, flat_amount: 2500 } &&
          tiers[1].slice(:up_to, :unit_amount, :flat_amount) == { up_to: nil, unit_amount: 500, flat_amount: 0 }
        raise ConfigurationError, "Profile price differs from the approved test plan; nothing existing was changed." unless valid
      end

      def validate_portal!(portal, price)
        valid = portal.livemode == false && portal.active && !portal.is_default &&
          contains_settings?(portal.to_hash[:features], portal_features(price))
        raise ConfigurationError, "Profile portal differs from the approved test configuration; nothing existing was changed." unless valid
      end

      def contains_settings?(actual, expected)
        case expected
        when Hash
          actual.is_a?(Hash) && expected.all? { |key, value| contains_settings?(actual[key], value) }
        when Array
          actual.is_a?(Array) && actual.size == expected.size &&
            expected.all? { |value| actual.any? { |item| contains_settings?(item, value) } }
        else
          actual == expected
        end
      end

      def request_options(**options)
        { api_key: @api_key }.merge(options)
      end
  end
end
