module Billing
  class PortalSessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_current_account!
    before_action :require_account_admin!

    def create
      unless Billing::StripeConfig.portal_ready?(current_account)
        redirect_to billing_path, alert: "Stripe customer portal is not available yet."
        return
      end

      portal_session = Stripe::BillingPortal::Session.create(
        customer: current_account.stripe_customer_id,
        return_url: billing_url
      )

      redirect_to portal_session.url, allow_other_host: true, status: :see_other
    rescue Stripe::StripeError => e
      Rails.logger.error("stripe_portal_failed account_id=#{current_account.id} error_class=#{e.class.name} error_message=#{e.message.to_s.squish}")
      redirect_to billing_path, alert: "Stripe customer portal could not be started."
    end

    private

      def require_account_admin!
        return if current_user.super_admin? || current_user.can_manage_account?(current_account)

        redirect_to billing_path, alert: "Only account admins can manage subscriptions."
      end
  end
end
