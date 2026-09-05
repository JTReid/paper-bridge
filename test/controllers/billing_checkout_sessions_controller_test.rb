require "test_helper"

class BillingCheckoutSessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:greenfield).billing_subscription.update!(status: :incomplete)
  end

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
    checkout_session = stripe_checkout_session
    checkout_session_creator = lambda do |params, options|
      assert_equal "subscription", params[:mode]
      assert_equal "cus_test_123", params[:customer]
      assert_equal [ {
        price: "price_profile_123", quantity: 5,
        adjustable_quantity: { enabled: true, minimum: 5, maximum: 999_999 }
      } ], params[:line_items]
      assert_equal dashboard_url(checkout: "success"), params[:success_url]
      assert_equal billing_url(checkout: "cancel"), params[:cancel_url]
      assert_equal({ account_id: accounts(:greenfield).id.to_s }, params[:metadata])
      assert_not_includes params, :payment_method_types
      assert_match(/\Apaperbridge_checkout_[\h-]+\z/, options[:idempotency_key])

      checkout_session
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123") do
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
    assert_equal "cs_test_123", subscription.checkout_attempt.fetch("session_id")
  end

  test "clears the pending marker when Stripe cannot create checkout" do
    sign_in users(:family_admin)

    stripe_customer = Struct.new(:id).new("cus_test_123")
    checkout_failure = ->(*) { raise Stripe::APIError, "Stripe is unavailable" }

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123") do
        with_stubbed_singleton_method(Stripe::Customer, :create, stripe_customer) do
          with_stubbed_singleton_method(Stripe::Checkout::Session, :create, checkout_failure) do
            post billing_checkout_session_path
          end
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal "We couldn’t start checkout. Please try again.", flash[:alert]
    subscription = accounts(:greenfield).reload.billing_subscription
    assert_not subscription.checkout_pending?
    assert subscription.checkout_attempt.fetch("token").present?
  end

  test "starts checkout with enough quantity for existing managed profiles" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_test_123")
    (7 - account.dependents.count).times { |i| account.dependents.create!(first_name: "Profile #{i}") }
    sign_in users(:family_admin)

    creator = lambda do |params, _options|
      assert_equal 7, params[:line_items].first[:quantity]
      stripe_checkout_session
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123") do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
  end

  test "existing subscriptions must use the portal instead of buying a second subscription" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription

    %w[active trialing past_due unpaid paused incomplete].each do |status|
      subscription.update!(stripe_customer_id: "cus_test_123", stripe_subscription_id: "sub_existing", status: status)
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, ->(*) { flunk "Must not create duplicate checkout" }) do
        post billing_checkout_session_path
      end
      assert_redirected_to billing_path
      assert_equal "You already have a subscription. Use Manage billing to make changes.", flash[:alert]
      assert_not subscription.reload.checkout_pending?
    end
  end

  test "canceled and expired subscriptions can purchase a new plan" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription

    %w[canceled incomplete_expired].each do |status|
      subscription.reload
      subscription.clear_checkout_attempt
      subscription.update!(stripe_customer_id: "cus_test_123", stripe_subscription_id: "sub_old", status: status)
      with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
        with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123") do
          with_stubbed_singleton_method(Stripe::Checkout::Session, :create, stripe_checkout_session) do
            post billing_checkout_session_path
          end
        end
      end
      assert_redirected_to "https://checkout.stripe.test/session"
    end
  end

  test "active manually granted accounts cannot buy duplicate access" do
    accounts(:greenfield).billing_subscription.update!(status: :active)
    sign_in users(:family_admin)

    post billing_checkout_session_path

    assert_redirected_to billing_path
    assert_equal "You already have a subscription. Use Manage billing to make changes.", flash[:alert]
  end

  test "repeated and canceled checkout attempts reuse the same open Stripe session" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_customer_id: "cus_test_123")
    creations = 0
    creator = lambda do |*_args|
      creations += 1
      stripe_checkout_session
    end
    retriever = lambda do |id|
      assert_equal "cs_test_123", id
      stripe_checkout_session
    end

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, retriever) do
          post billing_checkout_session_path
          assert_redirected_to "https://checkout.stripe.test/session"
          post billing_checkout_session_path
          assert_redirected_to "https://checkout.stripe.test/session"
          get billing_path(checkout: "cancel")
          assert_not subscription.reload.checkout_pending?
          post billing_checkout_session_path
          assert_redirected_to "https://checkout.stripe.test/session"
        end
      end
    end

    assert_equal 1, creations
    assert subscription.reload.checkout_pending?
  end

  test "uncertain checkout errors retain the token and exact pricing snapshot for retry" do
    sign_in users(:family_admin)
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_test_123")
    requests = []
    creator = lambda do |params, options|
      requests << [ params, options ]
      raise Stripe::APIConnectionError, "Response lost" if requests.one?

      stripe_checkout_session
    end

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        post billing_checkout_session_path
        assert_redirected_to billing_path
        first_attempt = account.reload.billing_subscription.checkout_attempt.deep_dup
        assert first_attempt.fetch("token").present?
        (7 - account.dependents.count).times { |index| account.dependents.create!(first_name: "Profile #{index}") }
        with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_changed_after_request") do
          post billing_checkout_session_path
        end
        assert_redirected_to "https://checkout.stripe.test/session"
        assert_equal first_attempt.fetch("token"), account.reload.billing_subscription.checkout_attempt.fetch("token")
      end
    end

    assert_equal 2, requests.size
    assert_equal requests.first, requests.last
  end

  test "uncertain customer creation retries with the same idempotency key" do
    sign_in users(:family_admin)
    requests = []
    customer_creator = lambda do |params, options|
      requests << [ params, options ]
      raise Stripe::APIConnectionError, "Response lost" if requests.one?

      Struct.new(:id).new("cus_test_123")
    end

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Customer, :create, customer_creator) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, stripe_checkout_session) do
          post billing_checkout_session_path
          assert_redirected_to billing_path
          post billing_checkout_session_path
          assert_redirected_to "https://checkout.stripe.test/session"
        end
      end
    end

    assert_equal 2, requests.size
    assert_equal requests.first, requests.last
    assert_match(/\Apaperbridge_customer_/, requests.last.last.fetch(:idempotency_key))
  end

  test "completed checkout waits for webhooks instead of creating another subscription" do
    sign_in users(:family_admin)
    subscription = seed_checkout_attempt
    subscription.update!(status: :canceled, stripe_subscription_id: "sub_old")

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(status: "complete", subscription: "sub_new")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, ->(*) { flunk "Completed checkout must not be replaced" }) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to dashboard_url(checkout: "success")
    assert subscription.reload.checkout_pending?
    assert_equal "sub_old", subscription.stripe_subscription_id
    assert_nil subscription.profile_limit
  end

  test "expired sessions get a new attempt and idempotency key" do
    sign_in users(:family_admin)
    subscription = seed_checkout_attempt
    old_token = subscription.checkout_attempt.fetch("token")

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(status: "expired")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, stripe_checkout_session(id: "cs_new")) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert_not_equal old_token, subscription.reload.checkout_attempt.fetch("token")
    assert_equal "cs_new", subscription.checkout_attempt.fetch("session_id")
  end

  test "an incomplete subscription can resume its own open checkout after payment failure" do
    sign_in users(:family_admin)
    subscription = seed_checkout_attempt
    subscription.update!(status: :incomplete, stripe_subscription_id: "sub_pending")

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(subscription: "sub_pending")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, ->(*) { flunk "Must resume the existing session" }) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert subscription.reload.checkout_pending?
  end

  test "an expired checkout cannot start a second nonterminal subscription" do
    sign_in users(:family_admin)
    subscription = seed_checkout_attempt
    subscription.update!(status: :incomplete, stripe_subscription_id: "sub_pending")

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(status: "expired", subscription: "sub_pending")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, ->(*) { flunk "Must not create a second subscription" }) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to billing_path
    assert_nil subscription.reload.checkout_attempt
    assert_not subscription.checkout_pending?
  end

  test "a completed session for a canceled subscription does not prevent resubscribing" do
    sign_in users(:family_admin)
    subscription = seed_checkout_attempt
    subscription.update!(status: :canceled, stripe_subscription_id: "sub_old")
    old_token = subscription.checkout_attempt.fetch("token")

    with_checkout_config do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(status: "complete", subscription: "sub_old")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, stripe_checkout_session(id: "cs_new")) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert_not_equal old_token, subscription.reload.checkout_attempt.fetch("token")
    assert_equal "cs_new", subscription.checkout_attempt.fetch("session_id")
  end

  test "eligible launch checkout requires payment details and applies ninety free days to every selected profile" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_customer_id: "cus_test_123", stripe_price_id: nil)
    sign_in users(:family_admin)
    creator = lambda do |params, _options|
      assert_equal "always", params[:payment_method_collection]
      assert_equal "pmc_cards", params[:payment_method_configuration]
      assert_not_includes params, :payment_method_types
      assert_equal 90, params[:subscription_data][:trial_period_days]
      assert_not_includes params[:subscription_data], :trial_end
      assert_equal({ end_behavior: { missing_payment_method: "cancel" } }, params[:subscription_data][:trial_settings])
      assert_equal({ account_id: subscription.account_id.to_s }, params[:subscription_data][:metadata])
      assert_equal 1, params[:line_items].size
      assert_equal "price_profile_123", params[:line_items].first[:price]
      assert params[:line_items].first[:adjustable_quantity][:enabled]
      stripe_checkout_session
    end

    with_launch_checkout do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        post billing_checkout_session_path
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert_equal 90, subscription.reload.checkout_attempt.fetch("trial_period_days")
    assert_nil subscription.launch_trial_used_at
    assert_not subscription.active_for_access?, "Only a signed lifecycle webhook activates trial access"
  end

  test "the launch switch disables the offer and ignores client supplied trial settings" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_customer_id: "cus_test_123", stripe_price_id: nil)
    sign_in users(:family_admin)
    creator = lambda do |params, _options|
      assert_not_includes params[:subscription_data], :trial_period_days
      assert_not_includes params[:subscription_data], :trial_settings
      stripe_checkout_session
    end

    with_launch_checkout(enabled: false) do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        post billing_checkout_session_path, params: { trial_period_days: 90, launch_trial_enabled: true }
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert_nil subscription.reload.checkout_attempt["trial_period_days"]
  end

  test "returning subscribers and previously used trials are not offered another launch trial" do
    subscription = accounts(:greenfield).billing_subscription
    sign_in users(:family_admin)
    creator = lambda do |params, _options|
      assert_not_includes params[:subscription_data], :trial_period_days
      stripe_checkout_session
    end

    with_launch_checkout do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        [
          { status: :canceled, stripe_subscription_id: "sub_paid_before" },
          { status: :incomplete_expired, stripe_subscription_id: "sub_expired_before" },
          { status: :incomplete, stripe_subscription_id: nil, launch_trial_used_at: 90.days.ago },
          { status: :incomplete, stripe_subscription_id: nil, trial_end: 1.day.ago },
          { status: :incomplete, stripe_subscription_id: nil, stripe_price_id: "price_legacy" }
        ].each do |history|
          subscription.update!({
            stripe_customer_id: "cus_test_123", stripe_price_id: nil,
            launch_trial_used_at: nil, trial_end: nil, metadata: {}
          }.merge(history))
          post billing_checkout_session_path
          assert_redirected_to "https://checkout.stripe.test/session"
          assert_nil subscription.reload.checkout_attempt["trial_period_days"]
        end
      end
    end
  end

  test "uncertain trial checkout retries preserve the full request after the offer closes" do
    assert_trial_retry_preserves_request(initially_enabled: true)
  end

  test "uncertain paid checkout retries preserve the full request after the offer opens" do
    assert_trial_retry_preserves_request(initially_enabled: false)
  end

  test "an expired uncompleted trial checkout does not consume the offer and a replacement follows the current switch" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription
    subscription.start_checkout_attempt(price_id: "price_profile_123", quantity: 5, trial_period_days: 90)
    subscription.record_checkout_session("cs_test_123")
    subscription.update!(stripe_customer_id: "cus_test_123", stripe_price_id: nil)
    old_token = subscription.checkout_attempt.fetch("token")
    creator = lambda do |params, _options|
      assert_not_includes params[:subscription_data], :trial_period_days
      stripe_checkout_session(id: "cs_replacement")
    end

    with_launch_checkout(enabled: false) do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, stripe_checkout_session(status: "expired")) do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
          post billing_checkout_session_path
        end
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
    assert_nil subscription.reload.launch_trial_used_at
    assert subscription.launch_trial_eligible?
    assert_not_equal old_token, subscription.checkout_attempt.fetch("token")
    assert_nil subscription.checkout_attempt["trial_period_days"]
  end

  test "preexisting paid attempts without a trial field keep their original Stripe parameters" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_customer_id: "cus_test_123", stripe_price_id: nil, metadata: {
      "checkout_attempt" => { "token" => "before-trials", "price_id" => "price_profile_123", "quantity" => 5 }
    })
    creator = lambda do |params, options|
      assert_equal({ metadata: { account_id: subscription.account_id.to_s } }, params[:subscription_data])
      assert_not_includes params, :payment_method_collection
      assert_not_includes params, :payment_method_configuration
      assert_equal "paperbridge_checkout_before-trials", options[:idempotency_key]
      stripe_checkout_session
    end

    with_launch_checkout do
      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        post billing_checkout_session_path
      end
    end

    assert_redirected_to "https://checkout.stripe.test/session"
  end

  test "a consumed trial with a lost checkout response cannot be replayed when resubscribing" do
    sign_in users(:family_admin)
    subscription = accounts(:greenfield).billing_subscription

    [ { launch_trial_used_at: 100.days.ago }, { trial_end: 10.days.ago } ].each do |trial_history|
      subscription.update!({
        status: :canceled, stripe_subscription_id: "sub_previous_trial", stripe_customer_id: "cus_test_123",
        launch_trial_used_at: nil, trial_end: nil,
        metadata: { checkout_attempt: {
          token: "old_trial_response_lost", price_id: "price_profile_123", quantity: 5, trial_period_days: 90
        } }
      }.merge(trial_history))
      creator = lambda do |params, options|
        assert_not_includes params[:subscription_data], :trial_period_days
        assert_not_includes params[:subscription_data], :trial_settings
        assert_not_equal "paperbridge_checkout_old_trial_response_lost", options[:idempotency_key]
        stripe_checkout_session
      end

      with_launch_checkout do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
          post billing_checkout_session_path
        end
      end

      assert_redirected_to "https://checkout.stripe.test/session"
      assert_not_equal "old_trial_response_lost", subscription.reload.checkout_attempt.fetch("token")
      assert_nil subscription.checkout_attempt["trial_period_days"]
      assert_not subscription.launch_trial_available?
    end
  end

  private

    def with_launch_checkout(enabled: true, payment_method_configuration_id: "pmc_cards", &block)
      with_checkout_config do
        with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, enabled) do
          with_stubbed_singleton_method(Billing::StripeConfig, :payment_method_configuration_id, payment_method_configuration_id, &block)
        end
      end
    end

    def assert_trial_retry_preserves_request(initially_enabled:)
      sign_in users(:family_admin)
      subscription = accounts(:greenfield).billing_subscription
      subscription.update!(stripe_customer_id: "cus_test_123", stripe_price_id: nil)
      requests = []
      creator = lambda do |params, options|
        requests << [ params, options ]
        raise Stripe::APIConnectionError, "Response lost" if requests.one?

        stripe_checkout_session
      end

      with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
        with_launch_checkout(enabled: initially_enabled) { post billing_checkout_session_path }
        assert_redirected_to billing_path
        with_launch_checkout(enabled: !initially_enabled, payment_method_configuration_id: "pmc_changed") do
          post billing_checkout_session_path
        end
      end

      assert_redirected_to "https://checkout.stripe.test/session"
      assert_equal 2, requests.size
      assert_equal requests.first, requests.last
      assert_equal "pmc_cards", requests.first.first[:payment_method_configuration]
      if initially_enabled
        assert_equal 90, requests.first.first[:subscription_data][:trial_period_days]
      else
        assert_nil requests.first.first[:subscription_data][:trial_period_days]
      end
      assert_nil subscription.reload.launch_trial_used_at
    end

    def with_checkout_config(&block)
      with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
        with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profile_123", &block)
      end
    end

    def seed_checkout_attempt
      subscription = accounts(:greenfield).billing_subscription
      subscription.start_checkout_attempt(price_id: "price_profile_123", quantity: 5)
      subscription.record_checkout_session("cs_test_123")
      subscription.update!(stripe_customer_id: "cus_test_123")
      subscription
    end

    def stripe_checkout_session(id: "cs_test_123", status: "open", subscription: nil)
      Struct.new(:id, :url, :status, :subscription).new(id, "https://checkout.stripe.test/session", status, subscription)
    end
end
