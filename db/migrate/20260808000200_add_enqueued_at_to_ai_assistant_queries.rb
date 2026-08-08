class AddEnqueuedAtToAiAssistantQueries < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_assistant_queries, :enqueued_at, :datetime
  end
end
