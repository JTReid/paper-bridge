class CreateSavedAnswersAndMeetingPreps < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_answers do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dependent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :ai_assistant_query, foreign_key: { on_delete: :nullify }, index: false
      t.text :question, null: false
      t.jsonb :answer, null: false, default: {}
      t.string :title
      t.text :notes
      t.datetime :generated_at, null: false
      t.timestamps
    end

    add_index :saved_answers, [ :user_id, :ai_assistant_query_id ], unique: true,
      where: "ai_assistant_query_id IS NOT NULL"
    add_index :saved_answers, [ :account_id, :dependent_id, :user_id, :created_at ],
      name: "index_saved_answers_on_owner_and_created_at"

    create_table :meeting_preps do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dependent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :meeting_prep_answers do |t|
      t.references :meeting_prep, null: false, foreign_key: true
      t.references :saved_answer, null: false, foreign_key: true
      t.integer :position, null: false
      t.timestamps
    end

    add_index :meeting_prep_answers, [ :meeting_prep_id, :saved_answer_id ], unique: true
    add_index :meeting_prep_answers, [ :meeting_prep_id, :position ]
  end
end
