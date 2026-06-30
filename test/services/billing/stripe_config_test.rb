require "test_helper"

class Billing::StripeConfigTest < ActiveSupport::TestCase
  test "uses standard price credential for subscription price" do
    credentials = { standard_price: "price_standard_123", price_id: "price_legacy_123" }

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_equal "price_standard_123", Billing::StripeConfig.price_id
    end
  end

  test "supports legacy price id credential" do
    credentials = { price_id: "price_legacy_123" }

    with_stubbed_singleton_method(Billing::StripeConfig, :credentials, credentials) do
      assert_equal "price_legacy_123", Billing::StripeConfig.price_id
    end
  end
end
