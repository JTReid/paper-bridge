module SubscriptionGate
  extend ActiveSupport::Concern

  class_methods do
    def require_subscription!(**options)
      before_action :require_active_subscription!, **options
    end
  end

  private

    def require_active_subscription!
      return if current_user&.super_admin?
      return if current_account&.subscription_active?

      redirect_to billing_path, alert: "A subscription is required to continue."
    end
end
