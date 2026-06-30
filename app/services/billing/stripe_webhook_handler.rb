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

        subscription = account.billing_subscription || account.build_billing_subscription
        subscription.assign_attributes(
          stripe_customer_id: stripe_id(stripe_value(session, "customer")),
          stripe_subscription_id: stripe_id(stripe_value(session, "subscription")),
          stripe_price_id: Billing::StripeConfig.price_id,
          latest_event_id: event.id
        )
        subscription.save!
      end

      def sync_subscription(stripe_subscription, event)
        account = account_from_subscription(stripe_subscription)
        stripe_subscription_id = stripe_id(stripe_subscription)
        subscription = account&.billing_subscription ||
          BillingSubscription.find_or_initialize_by(stripe_subscription_id: stripe_subscription_id)
        return unless subscription.account || account

        subscription.account ||= account
        subscription.assign_attributes(
          stripe_customer_id: stripe_id(stripe_value(stripe_subscription, "customer")),
          stripe_subscription_id: stripe_subscription_id,
          stripe_price_id: stripe_price_id(stripe_subscription),
          status: normalized_status(stripe_value(stripe_subscription, "status")),
          current_period_end: stripe_time(subscription_period_end(stripe_subscription)),
          trial_end: stripe_time(stripe_value(stripe_subscription, "trial_end")),
          cancel_at_period_end: stripe_value(stripe_subscription, "cancel_at_period_end") == true,
          canceled_at: stripe_time(stripe_value(stripe_subscription, "canceled_at")),
          latest_event_id: event.id
        )
        subscription.save!
      end

      def mark_subscription_past_due(invoice, event)
        stripe_subscription_id = stripe_id(stripe_value(invoice, "subscription"))
        return if stripe_subscription_id.blank?

        subscription = BillingSubscription.find_by(stripe_subscription_id: stripe_subscription_id)
        subscription&.update!(status: :past_due, latest_event_id: event.id)
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

      def stripe_price_id(stripe_subscription)
        item = first_subscription_item(stripe_subscription)
        stripe_id(stripe_value(item, "price")) || Billing::StripeConfig.price_id
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
