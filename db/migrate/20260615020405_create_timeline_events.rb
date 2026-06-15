class CreateTimelineEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :timeline_events do |t|
      t.references :document_chunk, null: false, foreign_key: true
      t.string :event_type, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.date :occurred_on
      t.date :started_on
      t.date :ended_on
      t.string :date_precision, null: false
      t.string :date_source, null: false
      t.text :source_quote, null: false
      t.string :content_hash, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :timeline_events, [ :event_type, :occurred_on ]
    add_index :timeline_events, [ :date_source, :date_precision ]
    add_index :timeline_events, [ :document_chunk_id, :content_hash ], unique: true
  end
end
