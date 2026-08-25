module Billing
  class CheckoutSessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_current_account!
    before_action :require_account_admin!

    def create
      unless Billing::StripeConfig.checkout_ready?
        redirect_to billing_path, alert: "Online checkout isn’t available right now."
        return
      end

      billing_subscription = current_account.billing_subscription || current_account.build_billing_subscription
      billing_subscription.stripe_customer_id ||= create_stripe_customer.id
      billing_subscription.mark_checkout_pending
      billing_subscription.save!

      checkout_session = Stripe::Checkout::Session.create(
        mode: "subscription",
        customer: billing_subscription.stripe_customer_id,
        client_reference_id: current_account.id.to_s,
        line_items: [ { price: Billing::StripeConfig.price_id, quantity: 1 } ],
        success_url: dashboard_url(checkout: "success"),
        cancel_url: billing_url(checkout: "cancel"),
        metadata: stripe_metadata,
        subscription_data: { metadata: stripe_metadata }
      )

      redirect_to checkout_session.url, allow_other_host: true, status: :see_other
    rescue Stripe::StripeError => e
      clear_checkout_pending(billing_subscription)
      Rails.logger.error("stripe_checkout_failed account_id=#{current_account.id} error_class=#{e.class.name} error_message=#{e.message.to_s.squish}")
      redirect_to billing_path, alert: "We couldn’t start checkout. Please try again."
    end

    private

      def require_account_admin!
        return if current_user.super_admin? || current_user.can_manage_account?(current_account)

        redirect_to billing_path, alert: "Only the person who manages billing can change this subscription."
      end

      def create_stripe_customer
        Stripe::Customer.create(
          email: current_user.email,
          name: current_account.name,
          metadata: stripe_metadata
        )
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
