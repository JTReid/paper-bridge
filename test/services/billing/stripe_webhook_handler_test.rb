require "test_helper"
require "ostruct"
require "turbo/broadcastable/test_helper"

class Billing::StripeWebhookHandlerTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  test "checkout session completion records customer and subscription ids" do
    account = accounts(:greenfield)
    account.billing_subscription.mark_checkout_pending
    account.billing_subscription.save!
    event = stripe_event(
      "evt_checkout",
      "checkout.session.completed",
      OpenStruct.new(
        customer: "cus_test_123",
        subscription: "sub_test_123",
        client_reference_id: account.id.to_s,
        metadata: {}
      )
    )

    with_stubbed_singleton_method(Billing::StripeConfig, :price_id, "price_test_123") do
      assert_no_turbo_stream_broadcasts([ account, :billing_checkout ]) do
        Billing::StripeWebhookHandler.new.call(event)
      end
    end

    subscription = account.reload.billing_subscription

    assert_equal "cus_test_123", subscription.stripe_customer_id
    assert_equal "sub_test_123", subscription.stripe_subscription_id
    assert_equal "price_test_123", subscription.stripe_price_id
    assert_equal "evt_checkout", subscription.latest_event_id
    assert subscription.checkout_pending?
  end

  test "subscription update marks an account active" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      metadata: { "checkout_pending" => true }
    )
    stripe_subscription = OpenStruct.new(
      id: "sub_test_123",
      customer: "cus_test_123",
      status: "active",
      current_period_end: Time.zone.local(2026, 7, 27, 12, 0, 0).to_i,
      trial_end: nil,
      cancel_at_period_end: false,
      canceled_at: nil,
      metadata: { "account_id" => account.id.to_s },
      items: OpenStruct.new(data: [ OpenStruct.new(price: OpenStruct.new(id: "price_test_123")) ])
    )

    stream = capture_turbo_stream_broadcasts([ account, :billing_checkout ]) do
      Billing::StripeWebhookHandler.new.call(stripe_event("evt_subscription", "customer.subscription.updated", stripe_subscription))
    end.sole

    subscription = account.reload.billing_subscription

    assert_equal "active", subscription.status
    assert subscription.active_for_access?
    assert_equal "price_test_123", subscription.stripe_price_id
    assert_equal "evt_subscription", subscription.latest_event_id
    assert_not subscription.checkout_pending?
    assert_equal "refresh", stream["action"]
  end

  test "a provisional incomplete subscription keeps waiting for a decisive result" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      metadata: { "checkout_pending" => true }
    )
    stripe_subscription = OpenStruct.new(
      id: "sub_test_123",
      customer: "cus_test_123",
      status: "incomplete",
      current_period_end: nil,
      trial_end: nil,
      cancel_at_period_end: false,
      canceled_at: nil,
      metadata: { "account_id" => account.id.to_s },
      items: OpenStruct.new(data: [ OpenStruct.new(price: OpenStruct.new(id: "price_test_123")) ])
    )

    assert_no_turbo_stream_broadcasts([ account, :billing_checkout ]) do
      Billing::StripeWebhookHandler.new.call(stripe_event("evt_subscription_incomplete", "customer.subscription.updated", stripe_subscription))
    end

    subscription = account.reload.billing_subscription

    assert_equal "incomplete", subscription.status
    assert_equal "evt_subscription_incomplete", subscription.latest_event_id
    assert subscription.checkout_pending?
  end

  test "an expired incomplete subscription clears pending checkout and broadcasts" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      status: :incomplete,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      metadata: { "checkout_pending" => true }
    )
    stripe_subscription = OpenStruct.new(
      id: "sub_test_123",
      customer: "cus_test_123",
      status: "incomplete_expired",
      current_period_end: nil,
      trial_end: nil,
      cancel_at_period_end: false,
      canceled_at: nil,
      metadata: { "account_id" => account.id.to_s },
      items: OpenStruct.new(data: [ OpenStruct.new(price: OpenStruct.new(id: "price_test_123")) ])
    )

    stream = capture_turbo_stream_broadcasts([ account, :billing_checkout ]) do
      Billing::StripeWebhookHandler.new.call(stripe_event("evt_subscription_expired", "customer.subscription.updated", stripe_subscription))
    end.sole

    subscription = account.reload.billing_subscription

    assert_equal "incomplete_expired", subscription.status
    assert_equal "evt_subscription_expired", subscription.latest_event_id
    assert_not subscription.checkout_pending?
    assert_equal "refresh", stream["action"]
  end

  test "subscription update marks an account inactive for canceled status" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      status: :active,
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      metadata: { "checkout_pending" => true }
    )
    stripe_subscription = OpenStruct.new(
      id: "sub_test_123",
      customer: "cus_test_123",
      status: "canceled",
      current_period_end: Time.zone.local(2026, 7, 27, 12, 0, 0).to_i,
      trial_end: nil,
      cancel_at_period_end: false,
      canceled_at: Time.zone.local(2026, 6, 27, 12, 0, 0).to_i,
      metadata: { "account_id" => account.id.to_s },
      items: OpenStruct.new(data: [ OpenStruct.new(price: OpenStruct.new(id: "price_test_123")) ])
    )

    stream = capture_turbo_stream_broadcasts([ account, :billing_checkout ]) do
      Billing::StripeWebhookHandler.new.call(stripe_event("evt_subscription_canceled", "customer.subscription.deleted", stripe_subscription))
    end.sole

    subscription = account.reload.billing_subscription

    assert_equal "canceled", subscription.status
    assert_not subscription.active_for_access?
    assert_equal "evt_subscription_canceled", subscription.latest_event_id
    assert_not subscription.checkout_pending?
    assert_equal "refresh", stream["action"]
  end

  test "invoice payment failure marks subscription past due" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(
      status: :active,
      stripe_subscription_id: "sub_test_123",
      metadata: { "checkout_pending" => true }
    )
    invoice = OpenStruct.new(
      parent: OpenStruct.new(
        type: "subscription_details",
        subscription_details: OpenStruct.new(subscription: "sub_test_123")
      )
    )

    stream = capture_turbo_stream_broadcasts([ account, :billing_checkout ]) do
      Billing::StripeWebhookHandler.new.call(stripe_event("evt_invoice_failed", "invoice.payment_failed", invoice))
    end.sole

    subscription = account.reload.billing_subscription

    assert_equal "past_due", subscription.status
    assert_not subscription.active_for_access?
    assert_equal "evt_invoice_failed", subscription.latest_event_id
    assert_not subscription.checkout_pending?
    assert_equal "refresh", stream["action"]
  end

  private

    def stripe_event(id, type, object)
      OpenStruct.new(id: id, type: type, data: OpenStruct.new(object: object))
    end
end
