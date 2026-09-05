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

  test "eligible new accounts see the card required 90 day offer" do
    prepare_new_subscription
    sign_in users(:family_admin)

    with_launch_trial_configuration do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", text: /90 days free\. \$0 due today\. Card required\./
    assert_includes response.body, "After your trial, $25 USD/month covers up to five managed profiles."
    assert_includes response.body, "Each additional profile is $5 USD/month."
    assert_includes response.body, "Cancel before your trial ends to avoid being charged."
    assert_includes response.body, "One launch trial per family account."
    assert_includes response.body, "during the trial keeps it free and does not change its end date."
    assert_select "[data-testid='subscribe-button']", text: "Start 90-day free trial"
  end

  test "an account without a subscription record sees the launch offer without persisting a record" do
    accounts(:greenfield).billing_subscription.destroy!
    sign_in users(:family_admin)

    with_launch_trial_configuration do
      assert_no_difference("BillingSubscription.count") { get billing_path }
    end

    assert_select "[data-testid='launch-trial-offer']", count: 1
    assert_select "[data-testid='subscribe-button']", text: "Start 90-day free trial"
  end

  test "disabling new launch trials retains the ordinary paid checkout wording" do
    prepare_new_subscription
    sign_in users(:family_admin)

    with_launch_trial_configuration(enabled: false) do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", count: 0
    assert_select "[data-testid='subscribe-button']", text: "Subscribe"
    assert_not_includes response.body, "90 days free"
    assert_not_includes response.body, "$0 due today"
  end

  test "consumed trials do not advertise a second free trial" do
    subscription = prepare_new_subscription
    subscription.update!(launch_trial_used_at: 100.days.ago)
    sign_in users(:family_admin)

    with_launch_trial_configuration do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", count: 0
    assert_select "[data-testid='subscribe-button']", text: "Subscribe"
  end

  test "canceled trial subscriptions show a paid subscription option" do
    accounts(:greenfield).billing_subscription.update!(
      status: :canceled, stripe_subscription_id: "sub_canceled_trial",
      trial_end: 10.days.ago, launch_trial_used_at: 100.days.ago, profile_limit: 5
    )
    sign_in users(:family_admin)

    with_launch_trial_configuration do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", count: 0
    assert_select "[data-testid='billing-trial-details']", count: 0
    assert_select "[data-testid='subscribe-button']", text: "Subscribe"
    assert_not_includes response.body, "First payment is scheduled"
  end

  test "continuing a pending trial checkout preserves its offer when new trials are disabled" do
    subscription = prepare_new_subscription
    subscription.update!(metadata: { checkout_attempt: {
      token: "trial-checkout-token", price_id: "price_profiles", quantity: 5,
      session_id: "cs_trial_open", trial_period_days: 90
    } })
    sign_in users(:family_admin)

    with_launch_trial_configuration(enabled: false) do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", count: 1
    assert_select "[data-testid='subscribe-button']", text: "Continue Checkout"
  end

  test "continuing an existing paid checkout does not advertise a newly enabled trial" do
    subscription = prepare_new_subscription
    subscription.update!(metadata: { checkout_attempt: {
      token: "paid-checkout-token", price_id: "price_profiles", quantity: 5, session_id: "cs_paid_open"
    } })
    sign_in users(:family_admin)

    with_launch_trial_configuration do
      get billing_path
    end

    assert_select "[data-testid='launch-trial-offer']", count: 0
    assert_select "[data-testid='subscribe-button']", text: "Continue Checkout"
  end

  test "active managed profile trials show zero now and the current allowance price after the trial" do
    trial_end = 30.days.from_now.change(hour: 12)
    accounts(:greenfield).billing_subscription.update!(
      status: :trialing, trial_end: trial_end, current_period_end: trial_end,
      profile_limit: 6, launch_trial_used_at: 60.days.ago
    )
    sign_in users(:family_admin)

    with_launch_trial_configuration(enabled: false) do
      get billing_path
    end

    assert_select "[data-testid='billing-trial-details']", text: /\$0 during your free trial/
    assert_includes response.body, "Trial ends #{I18n.l(trial_end.to_date, format: :long)}."
    assert_includes response.body, "After the trial: $30 USD/month for your current allowance of 6 managed profiles."
    assert_includes response.body, "First payment is scheduled for #{I18n.l(trial_end.to_date, format: :long)} unless you cancel before then."
    assert_includes response.body, "including any scheduled allowance changes"
    assert_not_includes response.body, "Renews"
    assert_select "[data-testid='launch-trial-offer']", count: 0
    assert_select "[data-testid='subscribe-button']", count: 0
  end

  test "the five profile trial shows the base monthly amount" do
    accounts(:greenfield).billing_subscription.update!(status: :trialing, trial_end: 30.days.from_now, profile_limit: 5)
    sign_in users(:family_admin)

    get billing_path

    assert_includes response.body, "After the trial: $25 USD/month for your current allowance of 5 managed profiles."
  end

  test "a trial scheduled to cancel does not promise a future payment" do
    trial_end = 30.days.from_now
    accounts(:greenfield).billing_subscription.update!(
      status: :trialing, trial_end: trial_end, current_period_end: trial_end,
      profile_limit: 6, cancel_at_period_end: true
    )
    sign_in users(:family_admin)

    get billing_path

    assert_includes response.body, "$0 during your free trial."
    assert_includes response.body, "Your subscription is set to cancel at the end of the trial and will not renew."
    assert_includes response.body, "Will not renew"
    assert_not_includes response.body, "First payment is scheduled"
    assert_not_includes response.body, "After the trial:"
    assert_not_includes response.body, "Renews"
  end

  test "a stale trial status does not promise zero charges after the trial has ended" do
    trial_end = 1.day.ago
    accounts(:greenfield).billing_subscription.update!(status: :trialing, trial_end: trial_end, profile_limit: 6)
    sign_in users(:family_admin)

    get billing_path

    assert_includes response.body, "Your trial ended #{I18n.l(trial_end.to_date, format: :long)}. Stripe is confirming your billing status."
    assert_includes response.body, "Trial ended — awaiting billing update"
    assert_not_includes response.body, "$0 during your free trial"
    assert_not_includes response.body, "First payment is scheduled"
  end

  test "a legacy trial does not display a fabricated managed profile price" do
    accounts(:greenfield).billing_subscription.update!(status: :trialing, trial_end: 30.days.from_now)
    sign_in users(:family_admin)

    get billing_path

    assert_select "[data-testid='profile-plan-pricing']", count: 0
    assert_includes response.body, "$0 during your free trial."
    assert_not_includes response.body, "$25"
    assert_not_includes response.body, "$5 USD/month"
    assert_not_includes response.body, "After the trial:"
    assert_not_includes response.body, "90 days"
  end

  test "a trial without its end date does not invent payment timing" do
    accounts(:greenfield).billing_subscription.update!(status: :trialing, trial_end: nil, profile_limit: 5)
    sign_in users(:family_admin)

    get billing_path

    assert_includes response.body, "See Stripe for your trial end date and upcoming billing details."
    assert_not_includes response.body, "First payment is scheduled"
    assert_not_includes response.body, "$0 during your free trial"
  end

  test "an existing unpaid subscription must be managed rather than purchased again" do
    accounts(:greenfield).billing_subscription.update!(status: :past_due, stripe_customer_id: "cus_existing", stripe_subscription_id: "sub_existing")
    sign_in users(:family_admin)
    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
        get billing_path
      end
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

    with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
      get billing_path
    end

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

  private

    def prepare_new_subscription
      accounts(:greenfield).billing_subscription.tap do |subscription|
        subscription.update!(
          status: :incomplete, stripe_subscription_id: nil, stripe_price_id: nil,
          trial_end: nil, launch_trial_used_at: nil, current_period_end: nil, canceled_at: nil, metadata: {}
        )
      end
    end

    def with_launch_trial_configuration(enabled: true, &block)
      with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, enabled) do
        with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true, &block)
      end
    end
end
