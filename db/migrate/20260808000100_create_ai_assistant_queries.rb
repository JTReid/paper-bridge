class CreateAiAssistantQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_assistant_queries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dependent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :question, null: false
      t.string :state, null: false, default: "queued"
      t.text :draft_answer
      t.jsonb :answer, null: false, default: {}
      t.integer :result_count
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at

      t.timestamps
    end

    add_index :ai_assistant_queries, [ :account_id, :dependent_id, :created_at ]
    add_index :ai_assistant_queries, [ :user_id, :created_at ]
  end
end
