require "test_helper"

class BillingPortalSessionsControllerTest < ActionDispatch::IntegrationTest
  test "requires an account admin" do
    sign_in users(:account_member)

    post billing_portal_session_path

    assert_redirected_to billing_path
    assert_equal "Only account admins can manage subscriptions.", flash[:alert]
  end

  test "redirects when portal is not available" do
    sign_in users(:family_admin)

    post billing_portal_session_path

    assert_redirected_to billing_path
    assert_equal "Stripe customer portal is not available yet.", flash[:alert]
  end

  test "redirects super admins without an account before portal" do
    sign_in users(:super_admin)

    post billing_portal_session_path

    assert_redirected_to admin_accounts_path
    assert_equal "An account is required to continue.", flash[:alert]
  end

  test "creates a stripe portal session" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_test_123", status: :active)
    sign_in users(:family_admin)

    portal_session = Struct.new(:url).new("https://billing.stripe.test/session")

    with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
      with_stubbed_singleton_method(Stripe::BillingPortal::Session, :create, portal_session) do
        post billing_portal_session_path
      end
    end

    assert_redirected_to "https://billing.stripe.test/session"
  end
end
