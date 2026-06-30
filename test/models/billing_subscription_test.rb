require "test_helper"

class BillingSubscriptionTest < ActiveSupport::TestCase
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
end
