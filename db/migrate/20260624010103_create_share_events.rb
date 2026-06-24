class CreateShareEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :share_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.string :recipient_email, null: false
      t.string :subject
      t.text :message
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.text :error_message

      t.timestamps
    end

    add_index :share_events, [ :account_id, :created_at ]
    add_index :share_events, [ :sender_id, :created_at ]
    add_index :share_events, [ :status, :created_at ]
  end
end
