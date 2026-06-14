class AddSummaryToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :summary, :jsonb, null: false, default: {}
    add_column :documents, :summarized_at, :datetime
  end
end
