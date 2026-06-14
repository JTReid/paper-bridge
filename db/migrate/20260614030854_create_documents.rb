class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "uploaded"
      t.string :original_filename
      t.string :content_type
      t.bigint :byte_size

      t.timestamps
    end

    add_index :documents, %i[user_id created_at]
    add_index :documents, %i[account_id created_at]
    add_index :documents, %i[account_id status]
    add_index :documents, :status
  end
end
