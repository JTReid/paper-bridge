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
end
