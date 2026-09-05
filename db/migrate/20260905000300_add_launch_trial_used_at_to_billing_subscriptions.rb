class AddLaunchTrialUsedAtToBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_subscriptions, :launch_trial_used_at, :datetime
  end
end
