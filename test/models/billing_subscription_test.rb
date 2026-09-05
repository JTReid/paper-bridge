require "test_helper"

class BillingSubscriptionTest < ActiveSupport::TestCase
  test "profile allowance is optional for legacy subscriptions and at least five when managed" do
    subscription = billing_subscriptions(:greenfield_active)
    assert subscription.valid?
    assert_nil subscription.profile_limit

    [ 0, 4, 5.5 ].each do |limit|
      subscription.profile_limit = limit
      assert_not subscription.valid?
    end
    [ 5, 8 ].each do |limit|
      subscription.profile_limit = limit
      assert subscription.valid?
    end
  end

  test "active and trialing subscriptions grant access" do
    subscription = BillingSubscription.new(status: :active)
    assert subscription.active_for_access?

    subscription.status = :trialing
    assert subscription.active_for_access?
  end

  test "non active statuses do not grant access" do
    (BillingSubscription.statuses.keys - %w[active trialing]).each do |status|
      subscription = BillingSubscription.new(status: status)
      assert_not subscription.active_for_access?, "#{status} should not grant access"
    end
  end

  test "tracks a pending checkout without replacing other metadata" do
    subscription = BillingSubscription.new(metadata: { "source" => "fixture" })

    subscription.mark_checkout_pending

    assert subscription.checkout_pending?
    assert_equal "fixture", subscription.metadata["source"]

    subscription.clear_checkout_pending

    assert_not subscription.checkout_pending?
    assert_equal({ "source" => "fixture" }, subscription.metadata)
  end

  test "only a new account without subscription history is eligible for the launch trial" do
    subscription = BillingSubscription.new
    assert subscription.launch_trial_eligible?
    subscription.stripe_customer_id = "cus_abandoned_checkout"
    assert subscription.launch_trial_eligible?, "A customer created for abandoned Checkout is still eligible"

    [
      { status: :canceled }, { status: :active }, { status: :trialing },
      { stripe_subscription_id: "sub_previous" }, { stripe_price_id: "price_previous" },
      { current_period_end: 1.day.ago }, { canceled_at: 1.day.ago },
      { trial_end: 1.day.ago }, { launch_trial_used_at: 90.days.ago }
    ].each do |history|
      assert_not BillingSubscription.new(history).launch_trial_eligible?, history.inspect
    end
  end

  test "launch trial availability honors the launch switch for new checkouts" do
    subscription = BillingSubscription.new
    with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, false) do
      assert_not subscription.launch_trial_available?
    end
    with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, true) do
      assert subscription.launch_trial_available?
      assert_not billing_subscriptions(:greenfield_active).launch_trial_available?
    end
  end

  test "checkout attempts pin the trial decision without consuming the offer" do
    subscription = BillingSubscription.new(metadata: { "source" => "test" })
    subscription.start_checkout_attempt(price_id: "price_profiles", quantity: 7, trial_period_days: 90,
      payment_method_configuration_id: "pmc_cards")
    with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, false) do
      assert subscription.launch_trial_available?
    end
    assert subscription.launch_trial_eligible?
    assert_nil subscription.launch_trial_used_at
    assert_equal 90, subscription.checkout_attempt.fetch("trial_period_days")
    assert_equal 7, subscription.checkout_attempt.fetch("quantity")
    assert_equal "pmc_cards", subscription.checkout_attempt.fetch("payment_method_configuration_id")
    assert_equal "test", subscription.metadata.fetch("source")

    subscription.launch_trial_used_at = Time.current
    assert_not subscription.launch_trial_available?
    subscription.launch_trial_used_at = nil
    subscription.status = :canceled
    assert_not subscription.launch_trial_available?
  end

  test "existing paid checkout attempts do not silently gain a launch trial" do
    subscription = BillingSubscription.new(metadata: {
      "checkout_attempt" => { "token" => "existing", "price_id" => "price_profiles", "quantity" => 5 }
    })
    with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, true) do
      assert_not subscription.launch_trial_available?
    end
  end
end
