class CreateDocumentPages < ActiveRecord::Migration[8.1]
  def change
    create_table :document_pages do |t|
      t.references :account, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.integer :page_number, null: false
      t.text :embedded_text
      t.text :ocr_text
      t.jsonb :metadata, null: false, default: {}
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :document_pages, %i[document_id page_number], unique: true
    add_index :document_pages, %i[account_id document_id]
    add_index :document_pages, :status
  end
end
