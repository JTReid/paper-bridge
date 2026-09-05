class AddProfileAllowanceToBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_subscriptions, :profile_limit, :integer
    add_column :billing_subscriptions, :stripe_subscription_event_created_at, :datetime
    add_check_constraint :billing_subscriptions, "profile_limit IS NULL OR profile_limit >= 5",
      name: "billing_subscriptions_profile_limit_minimum"
  end
end
