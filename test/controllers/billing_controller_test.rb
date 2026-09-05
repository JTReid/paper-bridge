require "test_helper"

class BillingControllerTest < ActionDispatch::IntegrationTest
  test "new subscriptions show monthly profile pricing" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    get billing_path

    assert_select "[data-testid='profile-plan-pricing']", text: /\$25 USD\/month covers up to five managed profiles/
    assert_includes response.body, "Each additional profile is $5 USD/month."
  end

  test "legacy active subscribers are not shown a replacement price" do
    sign_in users(:family_admin)
    get billing_path

    assert_select "[data-testid='profile-plan-pricing']", count: 0
  end

  test "an existing unpaid subscription must be managed rather than purchased again" do
    accounts(:greenfield).billing_subscription.update!(status: :past_due, stripe_customer_id: "cus_existing", stripe_subscription_id: "sub_existing")
    sign_in users(:family_admin)
    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      get billing_path
    end

    assert_select "[data-testid='subscribe-button']", count: 0
    assert_select "[data-testid='manage-subscription-button']", count: 1
  end

  test "an incomplete subscription can resume its own checkout attempt" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :incomplete, stripe_subscription_id: "sub_incomplete")
    subscription.start_checkout_attempt(price_id: "price_profiles", quantity: 5)
    subscription.record_checkout_session("cs_open")
    subscription.save!
    sign_in users(:family_admin)
    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      get billing_path
    end

    assert_select "[data-testid='subscribe-button']", text: "Continue Checkout"
  end

  test "shows purchased profile allowance without counting care team users" do
    accounts(:greenfield).billing_subscription.update!(profile_limit: 8)
    sign_in users(:family_admin)

    get billing_path

    assert_response :success
    assert_select "[data-testid='profile-allowance']", text: /2 of 8 managed profiles in use/
    assert_includes response.body, "Care team members and account logins do not count toward this allowance."
    assert_select "[data-testid='profile-allowance-billing-link']", count: 0
  end

  test "does not retroactively show an allowance for a legacy subscription" do
    sign_in users(:family_admin)

    get billing_path

    assert_response :success
    assert_select "[data-testid='profile-allowance']", count: 0
  end

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
    assert_includes response.body, "Ask the person who manages billing for your family account."
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

  test "returns a canceled checkout to billing with a notice" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.mark_checkout_pending
    subscription.save!
    sign_in users(:family_admin)

    get billing_path(checkout: "cancel")

    assert_redirected_to billing_path
    assert_equal "Checkout canceled. Your subscription hasn’t changed.", flash[:notice]
    assert_not subscription.reload.checkout_pending?
  end

  test "returns an inactive checkout result to billing with an alert" do
    sign_in users(:family_admin)

    get billing_path(checkout: "failed")

    assert_redirected_to billing_path
    assert_equal "Your subscription isn’t active yet. Review your billing details and try again.", flash[:alert]
  end

  test "redirects super admins without an account to admin accounts" do
    sign_in users(:super_admin)

    get billing_path

    assert_redirected_to admin_accounts_path
    assert_equal "We couldn’t find a family account for this sign-in.", flash[:alert]
  end
end
