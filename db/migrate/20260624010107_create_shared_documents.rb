class CreateSharedDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_documents do |t|
      t.references :share_event, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true

      t.timestamps
    end

    add_index :shared_documents, [ :share_event_id, :document_id ], unique: true
  end
end
