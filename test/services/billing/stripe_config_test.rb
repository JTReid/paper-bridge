require "test_helper"

class Billing::StripeConfigTest < ActiveSupport::TestCase
  setup do
    @stripe_environment = ENV.to_h.slice("STRIPE_PRICE_ID", "STRIPE_PROFILE_PRICE_ID", "STRIPE_PROFILE_PORTAL_CONFIGURATION_ID", "STRIPE_SECRET_KEY", "STRIPE_LAUNCH_TRIAL_ENABLED", "STRIPE_PAYMENT_METHOD_CONFIGURATION_ID")
    %w[STRIPE_PRICE_ID STRIPE_PROFILE_PRICE_ID STRIPE_PROFILE_PORTAL_CONFIGURATION_ID STRIPE_SECRET_KEY STRIPE_LAUNCH_TRIAL_ENABLED STRIPE_PAYMENT_METHOD_CONFIGURATION_ID].each { |key| ENV.delete(key) }
  end

  teardown do
    %w[STRIPE_PRICE_ID STRIPE_PROFILE_PRICE_ID STRIPE_PROFILE_PORTAL_CONFIGURATION_ID STRIPE_SECRET_KEY STRIPE_LAUNCH_TRIAL_ENABLED STRIPE_PAYMENT_METHOD_CONFIGURATION_ID].each { |key| ENV.delete(key) }
    ENV.update(@stripe_environment)
  end

  test "uses standard price credential for subscription price" do
    credentials = { standard_price: "price_standard_123", price_id: "price_legacy_123" }

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_equal "price_standard_123", Billing::StripeConfig.price_id
    end
  end

  test "the launch trial is ninety days and disabled unless explicitly enabled" do
    assert_equal 90, Billing::StripeConfig::LAUNCH_TRIAL_DAYS
    [ nil, false, "false", "", "invalid", "1" ].each do |value|
      with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { launch_trial_enabled: value }) do
        assert_not Billing::StripeConfig.launch_trial_enabled?, value.inspect
      end
    end
    [ true, "true", "TRUE" ].each do |value|
      with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { launch_trial_enabled: value }) do
        assert Billing::StripeConfig.launch_trial_enabled?, value.inspect
      end
    end
  end

  test "an explicit environment override can enable or disable credential launch trials" do
    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { launch_trial_enabled: true }) do
      ENV["STRIPE_LAUNCH_TRIAL_ENABLED"] = "false"
      assert_not Billing::StripeConfig.launch_trial_enabled?
    end
    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { launch_trial_enabled: false }) do
      ENV["STRIPE_LAUNCH_TRIAL_ENABLED"] = "true"
      assert Billing::StripeConfig.launch_trial_enabled?
    end
  end

  test "the launch offer waits for its dedicated payment method configuration" do
    credentials = {
      secret_key: "rk_test_placeholder", profile_price: "price_profiles",
      profile_portal_configuration: "bpc_profiles", launch_trial_enabled: true
    }
    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_not Billing::StripeConfig.checkout_ready?
      credentials[:payment_method_configuration] = "pmc_cards"
      assert_equal "pmc_cards", Billing::StripeConfig.payment_method_configuration_id
      assert Billing::StripeConfig.checkout_ready?
      ENV["STRIPE_PAYMENT_METHOD_CONFIGURATION_ID"] = "pmc_environment"
      assert_equal "pmc_environment", Billing::StripeConfig.payment_method_configuration_id
    end
  end

  test "supports legacy price id credential" do
    credentials = { price_id: "price_legacy_123" }

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_equal "price_legacy_123", Billing::StripeConfig.price_id
    end
  end

  test "profile configuration uses separate credentials without replacing legacy settings" do
    credentials = {
      secret_key: "rk_test_placeholder", standard_price: "price_standard_123",
      profile_price: "price_profile_123", profile_portal_configuration: "bpc_profile_123"
    }

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_equal "price_standard_123", Billing::StripeConfig.price_id
      assert_equal "price_profile_123", Billing::StripeConfig.profile_price_id
      assert_equal "bpc_profile_123", Billing::StripeConfig.profile_portal_configuration_id
      assert Billing::StripeConfig.checkout_ready?
    end
  end

  test "profile environment settings take precedence" do
    ENV["STRIPE_PROFILE_PRICE_ID"] = "price_environment"
    ENV["STRIPE_PROFILE_PORTAL_CONFIGURATION_ID"] = "bpc_environment"

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { profile_price: "price_credential", profile_portal_configuration: "bpc_credential" }) do
      assert_equal "price_environment", Billing::StripeConfig.profile_price_id
      assert_equal "bpc_environment", Billing::StripeConfig.profile_portal_configuration_id
    end
  end

  test "legacy price alone does not enable the new checkout" do
    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { secret_key: "rk_test_placeholder", standard_price: "price_standard_123" }) do
      assert_nil Billing::StripeConfig.profile_price_id
      assert_not Billing::StripeConfig.checkout_ready?
    end
  end

  test "checkout waits for the dedicated portal configuration" do
    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { secret_key: "rk_test_placeholder", profile_price: "price_profile_123" }) do
      assert_not Billing::StripeConfig.checkout_ready?
    end
  end

  test "profile plan detection survives missing or changed current price configuration" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.profile_limit = 7

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, nil) do
      assert Billing::StripeConfig.profile_plan?(subscription)
    end
  end

  test "profile price matches before its allowance is synchronized" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.stripe_price_id = "price_profile_123"

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123") do
      assert Billing::StripeConfig.profile_plan?(subscription)
      assert_not Billing::StripeConfig.profile_plan?(nil)
    end
  end

  test "legacy portal remains available without new profile configuration" do
    account = accounts(:greenfield)
    account.billing_subscription.stripe_customer_id = "cus_legacy_123"

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, { secret_key: "rk_test_placeholder" }) do
      assert Billing::StripeConfig.portal_ready?(account)
      assert_not Billing::StripeConfig.profile_plan?(account.billing_subscription)
    end
  end
end
