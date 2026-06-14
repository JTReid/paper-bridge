# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_14_033907) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "accounts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "llm_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["llm_id"], name: "index_agent_types_on_llm_id"
    t.index ["name"], name: "index_agent_types_on_name", unique: true
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "byte_size"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "original_filename"
    t.string "status", default: "uploaded", null: false
    t.datetime "summarized_at"
    t.jsonb "summary", default: {}, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "created_at"], name: "index_documents_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_documents_on_account_id_and_status"
    t.index ["account_id"], name: "index_documents_on_account_id"
    t.index ["status"], name: "index_documents_on_status"
    t.index ["user_id", "created_at"], name: "index_documents_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "json_schemas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "schema", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_json_schemas_on_name", unique: true
  end

  create_table "llms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "provider_class", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_llms_on_name", unique: true
  end

  create_table "pipeline_activities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "entries", default: [], null: false
    t.bigint "pipeline_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pipeline_run_id"], name: "index_pipeline_activities_on_pipeline_run_id"
  end

  create_table "pipeline_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "entries", default: [], null: false
    t.bigint "pipeline_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pipeline_run_id"], name: "index_pipeline_logs_on_pipeline_run_id"
  end

  create_table "pipeline_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.text "message"
    t.string "state", default: "pending", null: false
    t.bigint "subject_id"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["subject_type", "subject_id"], name: "index_pipeline_runs_on_subject"
    t.index ["user_id"], name: "index_pipeline_runs_on_user_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.bigint "agent_type_id", null: false
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.text "system_directive", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type_id"], name: "index_prompts_on_agent_type_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "family_admin", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id"], name: "index_users_on_account_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_types", "llms"
  add_foreign_key "documents", "accounts"
  add_foreign_key "documents", "users"
  add_foreign_key "pipeline_activities", "pipeline_runs"
  add_foreign_key "pipeline_logs", "pipeline_runs"
  add_foreign_key "pipeline_runs", "users"
  add_foreign_key "prompts", "agent_types"
  add_foreign_key "users", "accounts"
end
