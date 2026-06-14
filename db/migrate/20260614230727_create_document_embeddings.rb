class CreateDocumentEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :document_embeddings do |t|
      t.references :document_chunk, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :dimensions, null: false
      t.string :distance_metric, null: false
      t.halfvec :embedding, limit: 3072, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :document_embeddings, %i[document_chunk_id provider model], unique: true
    add_index :document_embeddings, %i[provider model dimensions]
  end
end
