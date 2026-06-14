class CreateDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :document_chunks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.references :document_page, null: false, foreign_key: true
      t.text :content, null: false
      t.string :content_hash, null: false
      t.string :label, null: false
      t.integer :chunk_index, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :document_chunks, %i[document_id chunk_index], unique: true
    add_index :document_chunks, %i[document_id content_hash], unique: true
    add_index :document_chunks, %i[account_id label]
    add_index :document_chunks, %i[document_page_id chunk_index]
  end
end
