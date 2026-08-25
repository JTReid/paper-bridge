require "test_helper"

class BillingCheckoutSessionsControllerTest < ActionDispatch::IntegrationTest
  test "requires an account admin" do
    sign_in users(:account_member)

    post billing_checkout_session_path

    assert_redirected_to billing_path
    assert_equal "Only the person who manages billing can change this subscription.", flash[:alert]
  end

  test "redirects when checkout is not configured" do
    sign_in users(:family_admin)

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, false) do
      post billing_checkout_session_path
    end

    assert_redirected_to billing_path
    assert_equal "Online checkout isn’t available right now.", flash[:alert]
  end

  test "redirects super admins without an account before checkout" do
    sign_in users(:super_admin)

    post billing_checkout_session_path

    assert_redirected_to admin_accounts_path
    assert_equal "We couldn’t find a family account for this sign-in.", flash[:alert]
  end

  test "creates a stripe customer and checkout session" do
    sign_in users(:family_admin)

    stripe_customer = Struct.new(:id).new("cus_test_123")
    checkout_session = Struct.new(:url).new("https://checkout.stripe.test/session")
    checkout_session_creator = lambda do |**params|
      assert_equal "subscription", params[:mode]
      assert_equal "cus_test_123", params[:customer]
      assert_equal [ { price: "price_test_123", quantity: 1 } ], params[:line_items]
      assert_equal dashboard_url(checkout: "success"), params[:success_url]
      assert_equal billing_url(checkout: "cancel"), params[:cancel_url]
      assert_equal({ account_id: accounts(:greenfield).id.to_s }, params[:metadata])
      assert_not_includes params, :payment_method_types

      checkout_session
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :price_id, "price_test_123") do
        with_stubbed_singleton_method(Stripe::Customer, :create, stripe_customer) do
          with_stubbed_singleton_method(Stripe::Checkout::Session, :create, checkout_session_creator) do
            post billing_checkout_session_path
          end
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal "cus_test_123", subscription.stripe_customer_id
    assert subscription.checkout_pending?
  end

  test "clears the pending marker when Stripe cannot create checkout" do
    sign_in users(:family_admin)

    stripe_customer = Struct.new(:id).new("cus_test_123")
    checkout_failure = ->(**) { raise Stripe::APIError, "Stripe is unavailable" }

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :price_id, "price_test_123") do
        with_stubbed_singleton_method(Stripe::Customer, :create, stripe_customer) do
          with_stubbed_singleton_method(Stripe::Checkout::Session, :create, checkout_failure) do
            post billing_checkout_session_path
          end
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal "We couldn’t start checkout. Please try again.", flash[:alert]
    assert_not accounts(:greenfield).reload.billing_subscription.checkout_pending?
  end
end
