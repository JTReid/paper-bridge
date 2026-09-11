class SimplifySavedAnswerQueryIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :saved_answers, :ai_assistant_query_id, unique: true,
      where: "ai_assistant_query_id IS NOT NULL"
    remove_index :saved_answers, [ :user_id, :ai_assistant_query_id ], unique: true,
      where: "ai_assistant_query_id IS NOT NULL"
  end
end
