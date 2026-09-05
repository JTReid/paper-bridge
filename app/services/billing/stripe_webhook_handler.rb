module Billing
  class StripeWebhookHandler
    def call(event)
      return if duplicate_event?(event)

      case event.type
      when "checkout.session.completed"
        sync_checkout_session(event.data.object, event)
      when "customer.subscription.created", "customer.subscription.updated", "customer.subscription.deleted"
        sync_subscription(event.data.object, event)
      when "invoice.payment_failed"
        mark_subscription_past_due(event.data.object, event)
      end
    end

    private

      def duplicate_event?(event)
        event.id.present? && BillingSubscription.exists?(latest_event_id: event.id)
      end

      def sync_checkout_session(session, event)
        account = account_from_metadata(session)
        return unless account

        account.with_lock do
          subscription = account.reload.billing_subscription || account.build_billing_subscription
          incoming_id = stripe_id(stripe_value(session, "subscription"))
          next unless incoming_id && accepts_subscription?(subscription, incoming_id)

          # Checkout confirms identity, not the purchased quantity or access. A
          # lifecycle webhook may already have arrived with the actual price.
          if subscription.stripe_subscription_id != incoming_id
            subscription.stripe_subscription_event_created_at = nil
          end
          subscription.assign_attributes(
            stripe_customer_id: stripe_id(stripe_value(session, "customer")),
            stripe_subscription_id: incoming_id,
            latest_event_id: event.id
          )
          subscription.save!
        end
      end

      def sync_subscription(stripe_subscription, event)
        subscription_to_broadcast = nil
        account = account_from_subscription(stripe_subscription)
        stripe_subscription_id = stripe_id(stripe_subscription)
        account ||= BillingSubscription.find_by(stripe_subscription_id: stripe_subscription_id)&.account
        return unless account && stripe_subscription_id

        account.with_lock do
          subscription = account.reload.billing_subscription || account.build_billing_subscription
          next unless accepts_subscription?(subscription, stripe_subscription_id)
          next if stale_subscription_event?(subscription, event, stripe_subscription_id)

          stripe_subscription = resolve_same_second_conflict(stripe_subscription, subscription, event)

          checkout_was_pending = subscription.checkout_pending?
          status = normalized_status(stripe_value(stripe_subscription, "status"))
          item = first_subscription_item(stripe_subscription)
          price_id = stripe_id(stripe_value(item, "price"))
          profile_limit = profile_limit_from_item(subscription, item, price_id)
          record_trial_usage(subscription, stripe_subscription, event)
          subscription.assign_attributes(
            stripe_customer_id: stripe_id(stripe_value(stripe_subscription, "customer")),
            stripe_subscription_id: stripe_subscription_id,
            stripe_price_id: price_id || subscription.stripe_price_id,
            profile_limit: profile_limit,
            status: status,
            current_period_end: stripe_time(subscription_period_end(stripe_subscription)),
            trial_end: stripe_time(stripe_value(stripe_subscription, "trial_end")),
            cancel_at_period_end: stripe_value(stripe_subscription, "cancel_at_period_end") == true,
            canceled_at: stripe_time(stripe_value(stripe_subscription, "canceled_at")),
            latest_event_id: event.id
          )
          subscription.stripe_subscription_event_created_at = stripe_time(stripe_value(event, "created")) if stripe_value(event, "created")
          subscription.clear_checkout_pending unless status == BillingSubscription.statuses[:incomplete]
          subscription.save!
          subscription_to_broadcast = subscription if checkout_was_pending && !subscription.checkout_pending?
        end
        broadcast_checkout_result(subscription_to_broadcast) if subscription_to_broadcast
      end

      def mark_subscription_past_due(invoice, event)
        # A failed prorated upgrade can leave the existing subscription paid and
        # active (Stripe pending updates). Its lifecycle event, not the failed
        # attempt's invoice, decides whether access or quantity actually changes.
        return if stripe_value(invoice, "billing_reason") == "subscription_update"

        subscription_to_broadcast = nil
        stripe_subscription_id = invoice_subscription_id(invoice)
        return if stripe_subscription_id.blank?

        subscription = BillingSubscription.find_by(stripe_subscription_id: stripe_subscription_id)
        return unless subscription

        subscription.account.with_lock do
          subscription.reload
          next unless subscription.stripe_subscription_id == stripe_subscription_id
          next if stale_subscription_event?(subscription, event, stripe_subscription_id)

          checkout_was_pending = subscription.checkout_pending?
          subscription.assign_attributes(status: :past_due, latest_event_id: event.id)
          subscription.stripe_subscription_event_created_at = stripe_time(stripe_value(event, "created")) if stripe_value(event, "created")
          subscription.clear_checkout_pending
          subscription.save!
          subscription_to_broadcast = subscription if checkout_was_pending
        end
        broadcast_checkout_result(subscription_to_broadcast) if subscription_to_broadcast
      end

      def accepts_subscription?(subscription, incoming_id)
        subscription.stripe_subscription_id.blank? ||
          subscription.stripe_subscription_id == incoming_id ||
          (subscription.checkout_pending? && (subscription.canceled? || subscription.incomplete_expired?))
      end

      def record_trial_usage(subscription, stripe_subscription, event)
        return if subscription.launch_trial_used_at.present?

        # Remember any historical trial before a later lifecycle event replaces
        # trial_end. An abandoned hosted Checkout does not consume the offer.
        trial_start = stripe_time(stripe_value(stripe_subscription, "trial_start"))
        trial_end = stripe_time(stripe_value(stripe_subscription, "trial_end"))
        return unless trial_start || trial_end || subscription.trial_end ||
          stripe_value(stripe_subscription, "status") == "trialing"

        subscription.launch_trial_used_at = trial_start || stripe_time(stripe_value(event, "created")) || Time.current
      end

      def stale_subscription_event?(subscription, event, incoming_id)
        return false unless subscription.stripe_subscription_id == incoming_id

        created_at = stripe_time(stripe_value(event, "created"))
        previous_at = subscription.stripe_subscription_event_created_at
        created_at && previous_at && created_at < previous_at
      end

      def profile_limit_from_item(subscription, item, price_id)
        configured_price = Billing::StripeConfig.profile_price_id
        profile_price = (configured_price.present? && price_id == configured_price) ||
          (subscription.profile_limit.present? && price_id == subscription.stripe_price_id)

        # Never turn a known profile plan into unlimited access because its
        # Stripe item is missing or an unexpected price was delivered.
        if subscription.profile_limit.present? && !profile_price
          raise ArgumentError, "Profile subscription has an unexpected Stripe price"
        end
        return unless profile_price

        quantity = stripe_value(item, "quantity")
        unless quantity.is_a?(Integer) && quantity.positive?
          raise ArgumentError, "Profile subscription requires a positive integer quantity"
        end

        [ quantity, BillingSubscription::INCLUDED_PROFILES ].max
      end

      def resolve_same_second_conflict(incoming, subscription, event)
        created_at = stripe_time(stripe_value(event, "created"))
        return incoming unless created_at && created_at == subscription.stripe_subscription_event_created_at &&
          subscription.stripe_subscription_id == stripe_id(incoming)

        item = first_subscription_item(incoming)
        price_id = stripe_id(stripe_value(item, "price"))
        quantity = stripe_value(item, "quantity")
        conflicting = normalized_status(stripe_value(incoming, "status")) != subscription.status ||
          price_id != subscription.stripe_price_id ||
          (subscription.profile_limit.present? && quantity.is_a?(Integer) && [ quantity, BillingSubscription::INCLUDED_PROFILES ].max != subscription.profile_limit) ||
          (stripe_value(incoming, "cancel_at_period_end") == true) != subscription.cancel_at_period_end?
        return incoming unless conflicting

        # Stripe's timestamps have only second precision and IDs are not ordered.
        # Only this ambiguous case needs a current snapshot; normal webhooks do
        # not fetch Stripe, and failures leave state unchanged for a retry.
        Stripe::Subscription.retrieve(subscription.stripe_subscription_id)
      end

      def invoice_subscription_id(invoice)
        parent = stripe_value(invoice, "parent")
        subscription_details = stripe_value(parent, "subscription_details")

        stripe_id(stripe_value(subscription_details, "subscription")) ||
          stripe_id(stripe_value(invoice, "subscription"))
      end

      def broadcast_checkout_result(subscription)
        Billing::CheckoutReturnBroadcaster.call(subscription)
      end

      def account_from_subscription(stripe_subscription)
        account_id = metadata_value(stripe_subscription, "account_id")
        return Account.find_by(id: account_id) if account_id.present?

        BillingSubscription.find_by(stripe_customer_id: stripe_id(stripe_value(stripe_subscription, "customer")))&.account
      end

      def account_from_metadata(object)
        account_id = metadata_value(object, "account_id") || stripe_value(object, "client_reference_id")
        Account.find_by(id: account_id)
      end

      def metadata_value(object, key)
        metadata = stripe_value(object, "metadata") || {}
        metadata = metadata.to_h if metadata.respond_to?(:to_h)
        metadata[key] || metadata[key.to_sym]
      end

      def stripe_id(value)
        return if value.blank?
        return value if value.is_a?(String)

        stripe_value(value, "id").presence
      end

      def stripe_time(value)
        return if value.blank?

        Time.zone.at(value.to_i)
      end

      def subscription_period_end(stripe_subscription)
        stripe_value(stripe_subscription, "current_period_end") ||
          stripe_value(first_subscription_item(stripe_subscription), "current_period_end")
      end

      def first_subscription_item(stripe_subscription)
        items = stripe_value(stripe_subscription, "items")
        data = stripe_value(items, "data")
        data&.first
      end

      def stripe_value(object, key)
        return if object.nil?

        key = key.to_s
        if object.is_a?(Hash)
          return object[key] if object.key?(key)

          symbol_key = key.to_sym
          return object[symbol_key] if object.key?(symbol_key)
          return
        end

        if object.respond_to?(:[])
          value = object[key]
          return value unless value.nil?
        end

        object.public_send(key) if object.respond_to?(key)
      end

      def normalized_status(status)
        status = status.to_s
        return status if BillingSubscription::STATUSES.value?(status)

        BillingSubscription.statuses[:incomplete]
      end
  end
end
