require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get billing_path

    assert_redirected_to new_user_session_path
  end

  test "renders setup required state before a stripe price exists" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, false) do
      get billing_path
    end

    assert_response :success
    assert_includes response.body, "Subscription required"
    assert_includes response.body, "Online subscription setup is not available yet."
    assert_includes response.body, "data-testid=\"nav-billing\""
    assert_not_includes response.body, "data-testid=\"nav-dashboard\""
    assert_not_includes response.body, "data-testid=\"nav-dependents\""
  end

  test "does not expose stripe implementation identifiers on customer billing page" do
    accounts(:greenfield).billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: nil,
      stripe_price_id: "price_test_123"
    )
    sign_in users(:family_admin)

    get billing_path

    assert_response :success
    assert_includes response.body, "Subscription required"
    assert_includes response.body, "Current status:"
    assert_includes response.body, "Not active"
    assert_not_includes response.body, "Stripe Customer"
    assert_not_includes response.body, "Stripe Subscription"
    assert_not_includes response.body, "cus_test_123"
    assert_not_includes response.body, "price_test_123"
  end

  test "account members can view billing but cannot manage it" do
    sign_in users(:account_member)

    get billing_path

    assert_response :success
    assert_includes response.body, "Ask an account admin to manage this subscription."
  end

  test "renders checkout form with turbo disabled for stripe redirect" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      get billing_path
    end

    assert_response :success
    assert_select "form[data-turbo='false'][action='#{billing_checkout_session_path}']" do
      assert_select "button[data-testid='subscribe-button']"
    end
  end

  test "renders portal form with turbo disabled for stripe redirect" do
    accounts(:greenfield).billing_subscription.update!(status: :active, stripe_customer_id: "cus_test_123")
    sign_in users(:family_admin)

    get billing_path

    assert_response :success
    assert_select "form[data-turbo='false'][action='#{billing_portal_session_path}']" do
      assert_select "button[data-testid='manage-subscription-button']", text: /Manage Subscription/
    end
  end

  test "redirects super admins without an account to admin accounts" do
    sign_in users(:super_admin)

    get billing_path

    assert_redirected_to admin_accounts_path
    assert_equal "An account is required to continue.", flash[:alert]
  end
end
