module Billing
  class PortalSessionsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_current_account!
    before_action :require_account_admin!

    def create
      unless Billing::StripeConfig.portal_ready?(current_account)
        redirect_to billing_path, alert: "Billing settings aren’t available right now."
        return
      end

      session_options = {
        customer: current_account.stripe_customer_id,
        return_url: billing_url
      }
      if Billing::StripeConfig.profile_plan?(current_account.billing_subscription)
        session_options[:configuration] = Billing::StripeConfig.profile_portal_configuration_id
      end

      portal_session = Stripe::BillingPortal::Session.create(**session_options)

      redirect_to portal_session.url, allow_other_host: true, status: :see_other
    rescue Stripe::StripeError => e
      Rails.logger.error("stripe_portal_failed account_id=#{current_account.id} error_class=#{e.class.name} error_message=#{e.message.to_s.squish}")
      redirect_to billing_path, alert: "We couldn’t open billing settings. Please try again."
    end

    private

      def require_account_admin!
        return if current_user.super_admin? || current_user.can_manage_account?(current_account)

        redirect_to billing_path, alert: "Only the person who manages billing can change this subscription."
      end
  end
end
