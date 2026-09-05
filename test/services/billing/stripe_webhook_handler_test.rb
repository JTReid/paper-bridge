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
    assert_equal "price_fixture_standard", subscription.stripe_price_id
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

  test "new profile subscriptions use the actual purchased quantity and include at least five" do
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      [ 1, 5, 6, 10 ].each_with_index do |quantity, index|
        Billing::StripeWebhookHandler.new.call(profile_event(quantity: quantity, created: 1_800_000_000 + index))

        subscription = accounts(:greenfield).reload.billing_subscription
        assert_equal [ quantity, 5 ].max, subscription.profile_limit
        assert_equal "price_profiles", subscription.stripe_price_id
        assert subscription.active_for_access?
      end
    end
  end

  test "legacy subscriptions remain unmanaged even when their quantity exceeds one" do
    event = profile_event(quantity: 20, price: "price_legacy")
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      Billing::StripeWebhookHandler.new.call(event)
    end

    assert_nil accounts(:greenfield).reload.billing_subscription.profile_limit
  end

  test "late checkout completion cannot overwrite lifecycle price quantity or access" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(profile_event(quantity: 8))
      handler.call(stripe_event("evt_late_checkout", "checkout.session.completed", {
        customer: "cus_profiles", subscription: "sub_profiles",
        metadata: { account_id: accounts(:greenfield).id.to_s }
      }))
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal "price_profiles", subscription.stripe_price_id
    assert_equal 8, subscription.profile_limit
    assert subscription.active_for_access?
    assert_equal Time.zone.at(1_800_000_000), subscription.stripe_subscription_event_created_at
  end

  test "scheduled and unpaid pending changes do not change current profile allowance" do
    event = profile_event(quantity: 8)
    event.data.object["schedule"] = "sub_sched_decrease_to_5"
    event.data.object["pending_update"] = { "subscription_items" => [ { "quantity" => 12 } ] }

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      Billing::StripeWebhookHandler.new.call(event)
    end

    assert_equal 8, accounts(:greenfield).reload.billing_subscription.profile_limit
  end

  test "a failed upgrade invoice does not revoke the existing paid profile allowance" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :active, stripe_subscription_id: "sub_profiles", profile_limit: 5)
    event = stripe_event("evt_failed_upgrade", "invoice.payment_failed", {
      subscription: "sub_profiles", billing_reason: "subscription_update"
    })

    Billing::StripeWebhookHandler.new.call(event)

    assert_equal 5, subscription.reload.profile_limit
    assert subscription.active_for_access?
  end

  test "a reduction applies on the new current item without deleting profiles or documents" do
    account = accounts(:greenfield)
    profile_ids = account.dependents.ids
    document_ids = account.documents.ids
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(profile_event(quantity: 8))
      handler.call(profile_event(quantity: 5, created: 1_800_000_100))
    end

    assert_equal 5, account.reload.billing_subscription.profile_limit
    assert_equal profile_ids.sort, account.dependents.ids.sort
    assert_equal document_ids.sort, account.documents.ids.sort
  end

  test "older quantity and invoice events cannot undo the latest allowance or status" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(profile_event(quantity: 8, created: 1_800_000_100))
      handler.call(profile_event(quantity: 5, created: 1_800_000_000))
      failure = stripe_event("evt_old_failure", "invoice.payment_failed", { subscription: "sub_profiles" })
      failure.created = 1_800_000_001
      handler.call(failure)
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal 8, subscription.profile_limit
    assert subscription.active_for_access?
  end

  test "duplicate lifecycle event does not change subscription twice" do
    handler = Billing::StripeWebhookHandler.new
    event = profile_event(quantity: 8)
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(event)
      assert_no_changes -> { accounts(:greenfield).reload.billing_subscription.updated_at } do
        handler.call(event)
      end
    end
  end

  test "same second conflicting events use the current Stripe state instead of delivery order" do
    handler = Billing::StripeWebhookHandler.new
    active = profile_event(quantity: 8)
    delayed = profile_event(quantity: 5)
    delayed.type = "customer.subscription.created"
    delayed.data.object["status"] = "incomplete"
    retrievals = []
    retrieve = ->(id) { retrievals << id; active.data.object }

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      with_stubbed_singleton_method(Stripe::Subscription, :retrieve, retrieve) do
        handler.call(active)
        assert_empty retrievals
        handler.call(delayed)
      end
    end

    assert_equal [ "sub_profiles" ], retrievals
    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal 8, subscription.profile_limit
    assert subscription.active_for_access?
  end

  test "failed same second reconciliation keeps allowance and access for a webhook retry" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(profile_event(quantity: 8))
      with_stubbed_singleton_method(Stripe::Subscription, :retrieve, ->(*) { raise Stripe::APIConnectionError, "Network unavailable" }) do
        assert_raises(Stripe::APIConnectionError) { handler.call(profile_event(quantity: 5)) }
      end
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal 8, subscription.profile_limit
    assert subscription.active_for_access?
  end

  test "checkout result broadcasts after the account update transaction exits" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :incomplete, metadata: { "checkout_pending" => true })
    outer_transaction_count = ActiveRecord::Base.connection.open_transactions
    broadcasts = []
    broadcast = lambda do |updated|
      broadcasts << updated.id
      assert_equal outer_transaction_count, ActiveRecord::Base.connection.open_transactions
      assert_equal 8, updated.reload.profile_limit
      assert updated.active_for_access?
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      with_stubbed_singleton_method(Billing::CheckoutReturnBroadcaster, :call, broadcast) do
        Billing::StripeWebhookHandler.new.call(profile_event(quantity: 8))
      end
    end
    assert_equal [ subscription.id ], broadcasts
  end

  test "events for an old subscription cannot replace the current subscription" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(profile_event(quantity: 8))
      old = profile_event(quantity: 5, created: 1_800_000_100)
      old.data.object["id"] = "sub_old"
      old.data.object["status"] = "canceled"
      handler.call(old)
      handler.call(stripe_event("evt_old_checkout", "checkout.session.completed", {
        customer: "cus_profiles", subscription: "sub_old", metadata: { account_id: accounts(:greenfield).id.to_s }
      }))
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert_equal "sub_profiles", subscription.stripe_subscription_id
    assert_equal 8, subscription.profile_limit
    assert subscription.active_for_access?
  end

  test "invalid profile quantities do not activate an account or grant unlimited access" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :incomplete)
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      [ nil, 0, -1, 1.5, "8" ].each do |quantity|
        assert_raises(ArgumentError) do
          Billing::StripeWebhookHandler.new.call(profile_event(quantity: quantity))
        end
      end
    end

    assert_nil subscription.reload.profile_limit
    assert_not subscription.active_for_access?
  end

  test "a known profile price remains managed if checkout configuration changes" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_price_id: "price_profiles", stripe_subscription_id: "sub_profiles", profile_limit: 5)
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_next_version") do
      Billing::StripeWebhookHandler.new.call(profile_event(quantity: 8))
    end
    assert_equal 8, subscription.reload.profile_limit
  end

  test "unexpected price cannot turn a profile subscription into unlimited access" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(stripe_price_id: "price_profiles", stripe_subscription_id: "sub_profiles", profile_limit: 5)
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      assert_raises(ArgumentError) do
        Billing::StripeWebhookHandler.new.call(profile_event(quantity: 20, price: "price_unexpected"))
      end
    end
    assert_equal 5, subscription.reload.profile_limit
  end

  test "a trusted trial lifecycle records usage and activates the entire profile allowance" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :incomplete, stripe_price_id: nil, metadata: { "checkout_pending" => true })
    event = trial_event

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      broadcasts = capture_turbo_stream_broadcasts([ subscription.account, :billing_checkout ]) do
        Billing::StripeWebhookHandler.new.call(event)
      end
      assert_equal 1, broadcasts.size
    end

    subscription.reload
    assert subscription.trialing?
    assert subscription.active_for_access?
    assert_equal 8, subscription.profile_limit
    assert_equal Time.zone.at(event.created), subscription.launch_trial_used_at
    assert_equal 90.days.to_i, subscription.trial_end.to_i - subscription.launch_trial_used_at.to_i
    assert_equal subscription.trial_end, subscription.current_period_end
    assert_not subscription.launch_trial_eligible?
    assert_not subscription.checkout_pending?
  end

  test "checkout completion alone does not consume a trial or grant access" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(status: :incomplete, stripe_price_id: nil)
    subscription.start_checkout_attempt(price_id: "price_profiles", quantity: 8, trial_period_days: 90)
    subscription.save!
    event = stripe_event("evt_checkout_trial", "checkout.session.completed", {
      customer: "cus_profiles", subscription: "sub_profiles", metadata: { account_id: subscription.account_id.to_s }
    })

    Billing::StripeWebhookHandler.new.call(event)

    assert_equal "sub_profiles", subscription.reload.stripe_subscription_id
    assert_nil subscription.launch_trial_used_at
    assert_nil subscription.trial_end
    assert_not subscription.launch_trial_eligible?, "Linked subscription identity prevents buying a second trial"
    assert_not subscription.active_for_access?
  end

  test "paid and canceled lifecycle events cannot erase consumed trial history" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(trial_event)
      paid = profile_event(quantity: 8, created: 1_800_000_001)
      handler.call(paid)
      subscription = accounts(:greenfield).reload.billing_subscription
      assert subscription.active?
      assert_nil subscription.trial_end
      assert_equal Time.zone.at(1_800_000_000), subscription.launch_trial_used_at

      canceled = profile_event(quantity: 8, created: 1_800_000_002)
      canceled.data.object["status"] = "canceled"
      handler.call(canceled)
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert subscription.canceled?
    assert_equal Time.zone.at(1_800_000_000), subscription.launch_trial_used_at
    assert_not subscription.launch_trial_available?
    assert_not subscription.launch_trial_eligible?
  end

  test "legacy trial evidence is remembered before a webhook clears its old trial end" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.update!(trial_end: 1.day.ago)

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      Billing::StripeWebhookHandler.new.call(profile_event(quantity: 8))
    end

    assert_nil subscription.reload.trial_end
    assert_equal Time.zone.at(1_800_000_000), subscription.launch_trial_used_at
    assert_not subscription.launch_trial_eligible?
  end

  test "trial end alone can establish historical trial usage on a nontrialing subscription" do
    event = profile_event(quantity: 8)
    event.data.object["trial_end"] = event.created - 30.days.to_i

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      Billing::StripeWebhookHandler.new.call(event)
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert subscription.active?
    assert_equal Time.zone.at(event.created), subscription.launch_trial_used_at
  end

  test "closing the launch offer and replaying stale events do not shorten an existing trial" do
    handler = Billing::StripeWebhookHandler.new
    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      handler.call(trial_event)
      with_stubbed_singleton_method(Billing::StripeConfig, :launch_trial_enabled?, false) do
        handler.call(profile_event(quantity: 5, created: 1_799_999_999))
        later = trial_event(created: 1_800_000_001)
        later.data.object["trial_start"] = 1_800_000_000
        later.data.object["trial_end"] = 1_800_000_000 + 90.days.to_i
        handler.call(later)
      end
    end

    subscription = accounts(:greenfield).reload.billing_subscription
    assert subscription.trialing?
    assert_equal 8, subscription.profile_limit
    assert_equal Time.zone.at(1_800_000_000), subscription.launch_trial_used_at
    assert_equal Time.zone.at(1_800_000_000 + 90.days.to_i), subscription.trial_end
  end

  test "a newly purchased subscription preserves the family account's consumed trial" do
    subscription = accounts(:greenfield).billing_subscription
    used_at = 100.days.ago.change(usec: 0)
    subscription.update!(status: :canceled, stripe_subscription_id: "sub_previous", launch_trial_used_at: used_at,
      metadata: { "checkout_pending" => true })

    with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_profiles") do
      Billing::StripeWebhookHandler.new.call(profile_event(quantity: 8))
    end

    assert_equal "sub_profiles", subscription.reload.stripe_subscription_id
    assert_equal used_at, subscription.launch_trial_used_at
    assert subscription.active?
    assert_not subscription.launch_trial_eligible?
  end

  private

    def trial_event(created: 1_800_000_000)
      event = profile_event(quantity: 8, created: created)
      event.id = "evt_trial_#{created}"
      event.data.object["status"] = "trialing"
      event.data.object["trial_start"] = created
      event.data.object["trial_end"] = created + 90.days.to_i
      event.data.object["items"]["data"].first["current_period_end"] = created + 90.days.to_i
      event
    end

    def profile_event(quantity:, created: 1_800_000_000, price: "price_profiles")
      event = stripe_event("evt_profiles_#{created}_#{quantity}", "customer.subscription.updated", {
        "id" => "sub_profiles", "customer" => "cus_profiles", "status" => "active",
        "metadata" => { "account_id" => accounts(:greenfield).id.to_s },
        "items" => { "data" => [ { "price" => { "id" => price }, "quantity" => quantity, "current_period_end" => created + 30.days.to_i } ] }
      })
      event.created = created
      event
    end

    def stripe_event(id, type, object)
      OpenStruct.new(id: id, type: type, data: OpenStruct.new(object: object))
    end
end
