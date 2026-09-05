require "test_helper"

class Billing::ProfilePlanSetupTest < ActiveSupport::TestCase
  TEST_KEY = "rk_test_placeholder"

  test "requires explicit confirmation before calling Stripe" do
    with_fake_stripe do
      assert_raises(Billing::ProfilePlanSetup::ConfigurationError) { setup_service.call }
    end
    assert_empty @stripe_calls
  end

  test "rejects live missing and unrecognized keys even with confirmation" do
    [ "sk_live_placeholder", "rk_live_placeholder", "pk_test_placeholder", "", nil ].each do |key|
      with_fake_stripe do
        assert_raises(Billing::ProfilePlanSetup::ConfigurationError) do
          Billing::ProfilePlanSetup.new(api_key: key).call(confirm_test_mode: true)
        end
      end
      assert_empty @stripe_calls
    end
  end

  test "creates the approved graduated price and dedicated hosted portal" do
    result = nil
    with_fake_stripe { result = setup_service.call(confirm_test_mode: true) }

    assert_equal({ price_id: "price_profiles_test", product_id: "prod_profiles_test", portal_configuration_id: "bpc_profiles_test" }, result)
    price_params = @stripe_calls.fetch(:price_create).first
    assert_equal "tiered", price_params[:billing_scheme]
    assert_equal "graduated", price_params[:tiers_mode]
    assert_equal "usd", price_params[:currency]
    assert_equal({ interval: "month", interval_count: 1, usage_type: "licensed" }, price_params[:recurring])
    assert_equal [ { up_to: 5, unit_amount: 0, flat_amount: 2500 }, { up_to: "inf", unit_amount: 500, flat_amount: 0 } ], price_params[:tiers]
    assert_equal "exclusive", price_params[:tax_behavior]
    assert_equal "profile", price_params.dig(:product_data, :unit_label)
    assert_operator price_params.dig(:product_data, :unit_label).length, :<=, 12

    portal_params = @stripe_calls.fetch(:portal_create).first
    assert_equal [ "features.subscription_update.products" ], portal_params[:expand]
    assert_equal [ "data.features.subscription_update.products" ], @stripe_calls.fetch(:portal_list).first[:expand]
    updates = portal_params.dig(:features, :subscription_update)
    assert_equal [ "quantity" ], updates[:default_allowed_updates]
    assert_equal "always_invoice", updates[:proration_behavior]
    assert_equal({ conditions: [ { type: "decreasing_item_amount" } ] }, updates[:schedule_at_period_end])
    assert_equal [ {
      product: "prod_profiles_test", prices: [ "price_profiles_test" ],
      adjustable_quantity: { enabled: true, minimum: 5, maximum: 999_999 }
    } ], updates[:products]
    assert_equal "at_period_end", portal_params.dig(:features, :subscription_cancel, :mode)
    assert_not_includes portal_params, :is_default
    assert_not_includes price_params, :transfer_lookup_key
    @stripe_calls.each_value { |(_params, options)| assert_equal TEST_KEY, options[:api_key] }
    assert @stripe_calls.fetch(:price_create).last[:idempotency_key].present?
    assert @stripe_calls.fetch(:portal_create).last[:idempotency_key].present?
  end

  test "the tier definition produces the approved monthly totals" do
    with_fake_stripe { setup_service.call(confirm_test_mode: true) }
    tiers = @stripe_calls.fetch(:price_create).first[:tiers]

    { 1 => 2500, 5 => 2500, 6 => 3000, 7 => 3500, 10 => 5000 }.each do |quantity, expected|
      total = tiers.first[:flat_amount] + [ quantity - tiers.first[:up_to], 0 ].max * tiers.last[:unit_amount]
      assert_equal expected, total
    end
  end

  test "rerunning reuses matching test objects without writes" do
    with_fake_stripe(existing_price: valid_price, existing_portal: valid_portal) do
      result = setup_service.call(confirm_test_mode: true)
      assert_equal "price_profiles_test", result[:price_id]
    end

    assert_equal [ :price_list, :portal_list ], @stripe_calls.keys
  end

  test "refuses a catalog price that does not match the agreed pricing" do
    price = valid_price
    price.tiers[1].unit_amount = 600

    with_fake_stripe(existing_price: price) do
      assert_raises(Billing::ProfilePlanSetup::ConfigurationError) { setup_service.call(confirm_test_mode: true) }
    end
    assert_equal [ :price_list ], @stripe_calls.keys
  end

  test "refuses a live object returned through test setup" do
    price = valid_price
    price.livemode = true

    with_fake_stripe(existing_price: price) do
      assert_raises(Billing::ProfilePlanSetup::ConfigurationError) { setup_service.call(confirm_test_mode: true) }
    end
    assert_equal [ :price_list ], @stripe_calls.keys
  end

  test "refuses to reuse the default portal or a changed downgrade policy" do
    [ :is_default, :wrong_policy ].each do |problem|
      portal = valid_portal
      if problem == :is_default
        portal.is_default = true
      else
        portal.features.subscription_update.proration_behavior = "none"
      end

      with_fake_stripe(existing_price: valid_price, existing_portal: portal) do
        assert_raises(Billing::ProfilePlanSetup::ConfigurationError) { setup_service.call(confirm_test_mode: true) }
      end
      assert_equal [ :price_list, :portal_list ], @stripe_calls.keys
    end
  end

  private

    def setup_service
      Billing::ProfilePlanSetup.new(api_key: TEST_KEY)
    end

    def valid_price
      Stripe::Price.construct_from({
        id: "price_profiles_test", product: "prod_profiles_test", active: true, livemode: false,
        currency: "usd", billing_scheme: "tiered", tiers_mode: "graduated", tax_behavior: "exclusive",
        recurring: { interval: "month", interval_count: 1, usage_type: "licensed" },
        tiers: [ { up_to: 5, unit_amount: 0, flat_amount: 2500 }, { up_to: nil, unit_amount: 500, flat_amount: 0 } ]
      })
    end

    def valid_portal
      Stripe::BillingPortal::Configuration.construct_from({
        id: "bpc_profiles_test", active: true, livemode: false, is_default: false,
        metadata: { paperbridge_plan: Billing::ProfilePlanSetup::VERSION, price_id: "price_profiles_test" },
        features: {
          customer_update: { enabled: true, allowed_updates: [ "email", "name", "address" ] },
          payment_method_update: { enabled: true },
          invoice_history: { enabled: true },
          subscription_cancel: { enabled: true, mode: "at_period_end", proration_behavior: "none" },
          subscription_update: {
            enabled: true, default_allowed_updates: [ "quantity" ], proration_behavior: "always_invoice",
            products: [ {
              product: "prod_profiles_test", prices: [ "price_profiles_test" ],
              adjustable_quantity: { enabled: true, minimum: 5, maximum: 999_999 }
            } ],
            schedule_at_period_end: { conditions: [ { type: "decreasing_item_amount" } ] }
          }
        }
      })
    end

    def with_fake_stripe(existing_price: nil, existing_portal: nil)
      @stripe_calls = {}
      price_list = lambda do |params, options|
        @stripe_calls[:price_list] = [ params, options ]
        Struct.new(:data).new([ existing_price ].compact)
      end
      price_create = lambda do |params, options|
        @stripe_calls[:price_create] = [ params, options ]
        valid_price
      end
      portal_list = lambda do |params, options|
        @stripe_calls[:portal_list] = [ params, options ]
        collection = Object.new
        collection.define_singleton_method(:auto_paging_each) { [ existing_portal ].compact.each }
        collection
      end
      portal_create = lambda do |params, options|
        @stripe_calls[:portal_create] = [ params, options ]
        valid_portal
      end

      with_stubbed_singleton_method(Stripe::Price, :list, price_list) do
        with_stubbed_singleton_method(Stripe::Price, :create, price_create) do
          with_stubbed_singleton_method(Stripe::BillingPortal::Configuration, :list, portal_list) do
            with_stubbed_singleton_method(Stripe::BillingPortal::Configuration, :create, portal_create) { yield }
          end
        end
      end
    end
end
