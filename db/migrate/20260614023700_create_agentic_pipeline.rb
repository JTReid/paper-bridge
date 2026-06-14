# frozen_string_literal: true

class CreateAgenticPipeline < ActiveRecord::Migration[8.1]
  def change
    create_table :llms do |t|
      t.string :name, null: false
      t.string :provider_class, null: false

      t.timestamps
    end
    add_index :llms, :name, unique: true

    create_table :agent_types do |t|
      t.string :name, null: false
      t.references :llm, null: false, foreign_key: true

      t.timestamps
    end
    add_index :agent_types, :name, unique: true

    create_table :prompts do |t|
      t.references :agent_type, null: false, foreign_key: true
      t.text :system_directive, null: false
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    create_table :json_schemas do |t|
      t.string :name, null: false
      t.jsonb :schema, null: false, default: {}

      t.timestamps
    end
    add_index :json_schemas, :name, unique: true

    create_table :pipeline_runs do |t|
      t.references :subject, polymorphic: true, index: true
      t.references :user, foreign_key: true, index: true
      t.string :state, default: "pending", null: false
      t.text :message
      t.jsonb :context, default: {}, null: false
      t.datetime :completed_at
      t.datetime :failed_at

      t.timestamps
    end

    create_table :pipeline_activities do |t|
      t.references :pipeline_run, null: false, foreign_key: true
      t.jsonb :entries, default: [], null: false

      t.timestamps
    end

    create_table :pipeline_logs do |t|
      t.references :pipeline_run, null: false, foreign_key: true
      t.jsonb :entries, default: [], null: false

      t.timestamps
    end
  end
end
