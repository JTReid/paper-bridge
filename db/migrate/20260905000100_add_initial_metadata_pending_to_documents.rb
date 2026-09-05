class AddInitialMetadataPendingToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :initial_metadata_pending, :boolean, default: false, null: false
  end
end
