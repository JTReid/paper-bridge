require "test_helper"
require "openssl"

class StripeWebhooksControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "whsec_test_secret"

  test "a signed profile subscription event persists the actual purchased allowance" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(status: :incomplete)
    object = real_shape_subscription_object(account, period_end: 1.month.from_now.to_i)
    object[:items][:data].first[:quantity] = 8
    object[:items][:data].first[:price][:id] = "price_profiles"
    payload = stripe_event_payload(id: "evt_signed_profile_quantity", type: "customer.subscription.created", object: object)

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      with_stripe_webhook_secret(WEBHOOK_SECRET) do
        post "/stripe/webhooks", params: payload, headers: stripe_headers(payload, WEBHOOK_SECRET)
      end
    end

    assert_response :success
    assert_equal 8, account.reload.billing_subscription.profile_limit
    assert account.subscription_active?
  end

  test "accepts a locally forwarded signed subscription webhook" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123"
    )
    payload = stripe_event_payload(
      id: "evt_local_subscription_active",
      type: "customer.subscription.updated",
      object: subscription_object(account, status: "active")
    )

    with_stripe_webhook_secret(WEBHOOK_SECRET) do
      post "/stripe/webhooks",
        params: payload,
        headers: stripe_headers(payload, WEBHOOK_SECRET)
    end

    assert_response :success

    subscription = account.reload.billing_subscription
    assert_equal "active", subscription.status
    assert subscription.active_for_access?
    assert_equal "evt_local_subscription_active", subscription.latest_event_id
  end

  test "accepts subscription webhooks with period data on the subscription item" do
    account = accounts(:greenfield)
    period_end = 1.month.from_now.to_i
    account.billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123"
    )
    payload = stripe_event_payload(
      id: "evt_local_subscription_item_period_active",
      type: "customer.subscription.updated",
      object: subscription_object(account, status: "active", current_period_end: period_end, period_on_item: true)
    )

    with_stripe_webhook_secret(WEBHOOK_SECRET) do
      post "/stripe/webhooks",
        params: payload,
        headers: stripe_headers(payload, WEBHOOK_SECRET)
    end

    assert_response :success

    subscription = account.reload.billing_subscription
    assert_equal "active", subscription.status
    assert_equal Time.zone.at(period_end), subscription.current_period_end
  end

  test "accepts reduced real stripe cli checkout and subscription webhook sequence" do
    account = accounts(:greenfield)
    period_end = 1.month.from_now.to_i
    account.billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: nil,
      stripe_subscription_id: nil,
      stripe_price_id: nil,
      current_period_end: nil
    )
    checkout_payload = stripe_event_payload(
      id: "evt_real_shape_checkout_completed",
      type: "checkout.session.completed",
      object: real_shape_checkout_session_object(account)
    )
    subscription_payload = stripe_event_payload(
      id: "evt_real_shape_subscription_created",
      type: "customer.subscription.created",
      object: real_shape_subscription_object(account, period_end: period_end)
    )

    with_stripe_webhook_secret(WEBHOOK_SECRET) do
      post "/stripe/webhooks",
        params: checkout_payload,
        headers: stripe_headers(checkout_payload, WEBHOOK_SECRET)
      assert_response :success

      post "/stripe/webhooks",
        params: subscription_payload,
        headers: stripe_headers(subscription_payload, WEBHOOK_SECRET)
    end

    assert_response :success

    subscription = account.reload.billing_subscription
    assert_equal "cus_UmitIsk6SBr2H4", subscription.stripe_customer_id
    assert_equal "sub_1TnekvL2vbOaKpVi47wIMOq3", subscription.stripe_subscription_id
    assert_equal "price_1Tn7R6L2vbOaKpViZUQbrDgi", subscription.stripe_price_id
    assert_equal "active", subscription.status
    assert_equal Time.zone.at(period_end), subscription.current_period_end
    assert subscription.active_for_access?
  end

  test "rejects unsigned webhook requests" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(status: :incomplete)
    payload = stripe_event_payload(
      id: "evt_unsigned_subscription_active",
      type: "customer.subscription.updated",
      object: subscription_object(account, status: "active")
    )

    with_stripe_webhook_secret(WEBHOOK_SECRET) do
      post "/stripe/webhooks",
        params: payload,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "Stripe-Signature" => "t=#{Time.current.to_i},v1=invalid"
        }
    end

    assert_response :bad_request
    assert_equal "incomplete", account.reload.billing_subscription.status
  end

  test "a signed trial lifecycle activates access and records the trial once" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(status: :incomplete, stripe_price_id: nil)
    start_at = Time.current.to_i
    end_at = start_at + 90.days.to_i
    object = real_shape_subscription_object(account, period_end: end_at)
    object.merge!(status: "trialing", trial_start: start_at, trial_end: end_at)
    object[:items][:data].first[:quantity] = 8
    object[:items][:data].first[:price][:id] = "price_profiles"
    payload = stripe_event_payload(id: "evt_signed_trial", type: "customer.subscription.created", object: object)

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      with_stripe_webhook_secret(WEBHOOK_SECRET) do
        post "/stripe/webhooks", params: payload, headers: stripe_headers(payload, WEBHOOK_SECRET)
        assert_response :success
        post "/stripe/webhooks", params: payload, headers: stripe_headers(payload, WEBHOOK_SECRET)
      end
    end

    assert_response :success
    subscription = account.reload.billing_subscription
    assert subscription.trialing?
    assert subscription.active_for_access?
    assert_equal 8, subscription.profile_limit
    assert_equal Time.zone.at(start_at), subscription.launch_trial_used_at
    assert_equal Time.zone.at(end_at), subscription.trial_end
    assert_not subscription.launch_trial_eligible?
  end

  test "an invalid signature cannot consume the trial or grant free access" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(status: :incomplete, stripe_price_id: nil)
    object = subscription_object(account, status: "trialing")
    object.merge!(trial_start: Time.current.to_i, trial_end: 90.days.from_now.to_i)
    payload = stripe_event_payload(id: "evt_unsigned_trial", type: "customer.subscription.created", object: object)

    with_stripe_webhook_secret(WEBHOOK_SECRET) do
      post "/stripe/webhooks", params: payload, headers: stripe_headers(payload, "whsec_invalid")
    end

    assert_response :bad_request
    subscription = account.reload.billing_subscription
    assert_nil subscription.launch_trial_used_at
    assert_nil subscription.trial_end
    assert subscription.launch_trial_eligible?
    assert_not subscription.active_for_access?
  end

  private

    def with_stripe_webhook_secret(secret)
      original = StripeEvent.signing_secret
      StripeEvent.signing_secret = secret

      yield
    ensure
      StripeEvent.signing_secret = original
    end

    def stripe_event_payload(id:, type:, object:)
      JSON.generate(
        id: id,
        object: "event",
        api_version: "2026-06-24.dahlia",
        type: type,
        data: { object: object }
      )
    end

    def real_shape_checkout_session_object(account)
      {
        id: "cs_test_a1SXtb7KcP13mYabgIwO3ghbiPwPMF5rVzz3AetWBzC8ih2f9rmrUGntb7",
        object: "checkout.session",
        client_reference_id: account.id.to_s,
        customer: "cus_UmitIsk6SBr2H4",
        metadata: { account_id: account.id.to_s },
        mode: "subscription",
        payment_status: "paid",
        status: "complete",
        subscription: "sub_1TnekvL2vbOaKpVi47wIMOq3"
      }
    end

    def real_shape_subscription_object(account, period_end:)
      {
        id: "sub_1TnekvL2vbOaKpVi47wIMOq3",
        object: "subscription",
        cancel_at_period_end: false,
        canceled_at: nil,
        customer: "cus_UmitIsk6SBr2H4",
        metadata: { account_id: account.id.to_s },
        status: "active",
        trial_end: nil,
        items: {
          object: "list",
          data: [
            {
              id: "si_UnFFP1N7kSOLPe",
              object: "subscription_item",
              current_period_end: period_end,
              current_period_start: 1.minute.ago.to_i,
              price: {
                id: "price_1Tn7R6L2vbOaKpViZUQbrDgi",
                object: "price",
                type: "recurring"
              },
              quantity: 1,
              subscription: "sub_1TnekvL2vbOaKpVi47wIMOq3"
            }
          ]
        }
      }
    end

    def subscription_object(account, status:, current_period_end: 1.month.from_now.to_i, period_on_item: false)
      subscription_item = {
        id: "si_test_123",
        object: "subscription_item",
        price: { id: "price_test_123", object: "price" }
      }
      subscription_item[:current_period_end] = current_period_end if period_on_item

      subscription = {
        id: "sub_test_123",
        object: "subscription",
        customer: "cus_test_123",
        status: status,
        trial_end: nil,
        cancel_at_period_end: false,
        canceled_at: nil,
        metadata: { account_id: account.id.to_s },
        items: {
          object: "list",
          data: [ subscription_item ]
        }
      }
      subscription[:current_period_end] = current_period_end unless period_on_item
      subscription
    end

    def stripe_headers(payload, secret)
      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)

      {
        "CONTENT_TYPE" => "application/json",
        "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
      }
    end
end
