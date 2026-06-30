class ApplicationController < ActionController::Base
  include SubscriptionGate

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :require_subscription_for_authenticated_account

  helper_method :current_account

  protected

    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: %i[name account_name])
      devise_parameter_sanitizer.permit(:account_update, keys: %i[name account_name])
    end

    def current_account
      @current_account ||= current_user&.account
    end

    def require_current_account!
      return if current_account.present?

      redirect_path = current_user&.super_admin? ? admin_accounts_path : root_path
      redirect_to redirect_path, alert: "An account is required to continue."
    end

    def after_sign_in_path_for(_resource)
      return admin_accounts_path if current_user&.super_admin?
      return billing_path if current_account.present? && !current_account.subscription_active?

      dashboard_path
    end

    def require_subscription_for_authenticated_account
      return unless user_signed_in?
      return if devise_controller?
      return if subscription_exempt_controller?
      return if current_user.super_admin?
      return if current_account.blank?
      return if current_account.subscription_active?

      redirect_to billing_path, alert: "A subscription is required to continue."
    end

    def subscription_exempt_controller?
      controller_path.in?(%w[billing billing/checkout_sessions billing/portal_sessions])
    end
end
