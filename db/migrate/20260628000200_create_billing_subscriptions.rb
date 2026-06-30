class CreateBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :billing_subscriptions do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :stripe_price_id
      t.string :status, null: false, default: "incomplete"
      t.datetime :current_period_end
      t.datetime :trial_end
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.string :latest_event_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :billing_subscriptions, :stripe_customer_id, unique: true
    add_index :billing_subscriptions, :stripe_subscription_id, unique: true
    add_index :billing_subscriptions, [ :status, :current_period_end ]
  end
end
