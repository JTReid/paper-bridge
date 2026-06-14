class AddPreparationToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :preparation_status, :string, null: false, default: "unprepared"
    add_column :documents, :prepared_payload, :jsonb, null: false, default: {}
    add_column :documents, :prepared_at, :datetime
    add_column :documents, :preparation_error, :text

    add_index :documents, :preparation_status
  end
end
