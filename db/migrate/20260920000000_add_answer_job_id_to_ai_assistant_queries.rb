class AddAnswerJobIdToAiAssistantQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_assistant_queries, :answer_job_id, :string
    add_index :ai_assistant_queries, :answer_job_id
  end
end
