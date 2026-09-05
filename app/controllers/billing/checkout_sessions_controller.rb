module Billing
  class CheckoutSessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_current_account!
    before_action :require_account_admin!

    def create
      # Serialize account administrators and retries with the webhook writer.
      # Stripe errors are rescued inside the transaction so an uncertain API
      # result does not discard the idempotency token needed on the next try.
      current_account.with_lock do
        billing_subscription = current_account.reload.billing_subscription || current_account.build_billing_subscription
        unless billing_subscription.can_start_checkout? || billing_subscription.can_resume_checkout?
          redirect_to billing_path, alert: "You already have a subscription. Use Manage billing to make changes."
          next
        end

        unless Billing::StripeConfig.checkout_ready?
          redirect_to billing_path, alert: "Online checkout isn’t available right now."
          next
        end

        redirect_to checkout_destination(billing_subscription), allow_other_host: true, status: :see_other
      rescue Stripe::StripeError => e
        clear_checkout_pending(billing_subscription)
        Rails.logger.error("stripe_checkout_failed account_id=#{current_account.id} error_class=#{e.class.name} error_message=#{e.message.to_s.squish}")
        redirect_to billing_path, alert: "We couldn’t start checkout. Please try again."
      end
    end

    private

      def require_account_admin!
        return if current_user.super_admin? || current_user.can_manage_account?(current_account)

        redirect_to billing_path, alert: "Only the person who manages billing can change this subscription."
      end

      def checkout_destination(subscription)
        if (session_id = subscription.checkout_attempt&.fetch("session_id", nil)).present?
          session = Stripe::Checkout::Session.retrieve(session_id)
          case session.status
          when "open"
            subscription.mark_checkout_pending
            subscription.save!
            return session.url
          when "complete"
            if session.subscription == subscription.stripe_subscription_id && (subscription.canceled? || subscription.incomplete_expired?)
              subscription.clear_checkout_attempt
            else
              subscription.mark_checkout_pending
              subscription.save!
              return dashboard_url(checkout: "success")
            end
          when "expired"
            subscription.clear_checkout_attempt
          else
            raise Stripe::APIError, "Unexpected Checkout session status"
          end
        end

        unless subscription.can_start_checkout? || subscription.checkout_attempt.present?
          subscription.clear_checkout_pending
          subscription.save! if subscription.changed?
          flash[:alert] = "You already have a subscription. Use Manage billing to make changes."
          return billing_url
        end

        unless subscription.checkout_attempt
          subscription.start_checkout_attempt(
            price_id: Billing::StripeConfig.profile_price_id,
            quantity: [ Billing::StripeConfig::INCLUDED_PROFILES, current_account.dependents.count ].max
          )
        end
        subscription.mark_checkout_pending
        subscription.save!
        attempt = subscription.checkout_attempt

        subscription.stripe_customer_id ||= create_stripe_customer(attempt.fetch("token")).id
        subscription.save! if subscription.changed?
        session = Stripe::Checkout::Session.create({
          mode: "subscription",
          customer: subscription.stripe_customer_id,
          client_reference_id: current_account.id.to_s,
          line_items: [ {
            price: attempt.fetch("price_id"),
            quantity: attempt.fetch("quantity"),
            adjustable_quantity: {
              enabled: true,
              minimum: Billing::StripeConfig::INCLUDED_PROFILES,
              maximum: Billing::StripeConfig::MAXIMUM_PROFILES
            }
          } ],
          success_url: dashboard_url(checkout: "success"),
          cancel_url: billing_url(checkout: "cancel"),
          metadata: stripe_metadata,
          subscription_data: { metadata: stripe_metadata }
        }, { idempotency_key: "paperbridge_checkout_#{attempt.fetch('token')}" })
        subscription.record_checkout_session(session.id)
        subscription.save!
        session.url
      end

      def create_stripe_customer(attempt_token)
        Stripe::Customer.create({
          email: current_user.email,
          name: current_account.name,
          metadata: stripe_metadata
        }, { idempotency_key: "paperbridge_customer_#{attempt_token}" })
      end

      def stripe_metadata
        { account_id: current_account.id.to_s }
      end

      def clear_checkout_pending(billing_subscription)
        return unless billing_subscription&.persisted?

        billing_subscription.clear_checkout_pending
        billing_subscription.save! if billing_subscription.changed?
      end
  end
end
