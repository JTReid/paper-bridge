require "test_helper"
require "turbo/broadcastable/test_helper"

class Billing::CheckoutReturnBroadcasterTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  test "refreshes the pending checkout return" do
    subscription = accounts(:greenfield).billing_subscription

    stream = capture_turbo_stream_broadcasts([ subscription.account, :billing_checkout ]) do
      Billing::CheckoutReturnBroadcaster.call(subscription)
    end.sole

    assert_equal "refresh", stream["action"]
  end

  test "does not interrupt webhook processing when cable delivery fails" do
    subscription = accounts(:greenfield).billing_subscription
    failure = ->(*) { raise "Cable is unavailable" }

    with_stubbed_singleton_method(Turbo::StreamsChannel, :broadcast_refresh_to, failure) do
      assert_nothing_raised { Billing::CheckoutReturnBroadcaster.call(subscription) }
    end
  end
end
