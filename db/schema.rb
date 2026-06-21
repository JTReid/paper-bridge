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

ActiveRecord::Schema[8.1].define(version: 2026_06_20_010100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "account_memberships", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "user_id"], name: "index_account_memberships_on_account_id_and_user_id", unique: true
    t.index ["account_id"], name: "index_account_memberships_on_account_id"
    t.index ["user_id", "role"], name: "index_account_memberships_on_user_id_and_role"
    t.index ["user_id"], name: "index_account_memberships_on_user_id"
  end

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

  create_table "care_team_memberships", force: :cascade do |t|
    t.datetime "accepted_at"
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "dependent_id", null: false
    t.string "email", null: false
    t.datetime "invited_at"
    t.bigint "invited_by_id", null: false
    t.string "name", null: false
    t.jsonb "permissions", default: {}, null: false
    t.datetime "revoked_at"
    t.string "role", null: false
    t.string "status", default: "invited", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "status"], name: "index_care_team_memberships_on_account_id_and_status"
    t.index ["account_id"], name: "index_care_team_memberships_on_account_id"
    t.index ["dependent_id", "user_id"], name: "index_care_team_memberships_on_dependent_id_and_user_id", unique: true
    t.index ["dependent_id"], name: "index_care_team_memberships_on_dependent_id"
    t.index ["email"], name: "index_care_team_memberships_on_email"
    t.index ["invited_by_id"], name: "index_care_team_memberships_on_invited_by_id"
    t.index ["user_id"], name: "index_care_team_memberships_on_user_id"
  end

  create_table "dependents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.date "date_of_birth"
    t.string "grade"
    t.string "name", null: false
    t.text "notes"
    t.string "school"
    t.datetime "updated_at", null: false
    t.index ["account_id", "name"], name: "index_dependents_on_account_id_and_name"
    t.index ["account_id"], name: "index_dependents_on_account_id"
  end

  create_table "document_chunks", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.integer "chunk_index", null: false
    t.text "content", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.bigint "document_page_id", null: false
    t.string "label", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "label"], name: "index_document_chunks_on_account_id_and_label"
    t.index ["account_id"], name: "index_document_chunks_on_account_id"
    t.index ["document_id", "chunk_index"], name: "index_document_chunks_on_document_id_and_chunk_index", unique: true
    t.index ["document_id", "content_hash"], name: "index_document_chunks_on_document_id_and_content_hash", unique: true
    t.index ["document_id"], name: "index_document_chunks_on_document_id"
    t.index ["document_page_id", "chunk_index"], name: "index_document_chunks_on_document_page_id_and_chunk_index"
    t.index ["document_page_id"], name: "index_document_chunks_on_document_page_id"
  end

  create_table "document_embeddings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dimensions", null: false
    t.string "distance_metric", null: false
    t.bigint "document_chunk_id", null: false
    t.halfvec "embedding", limit: 3072, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "model", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["document_chunk_id", "provider", "model"], name: "idx_on_document_chunk_id_provider_model_d597da71f5", unique: true
    t.index ["document_chunk_id"], name: "index_document_embeddings_on_document_chunk_id"
    t.index ["provider", "model", "dimensions"], name: "index_document_embeddings_on_provider_and_model_and_dimensions"
  end

  create_table "document_pages", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.text "embedded_text"
    t.jsonb "metadata", default: {}, null: false
    t.text "ocr_text"
    t.integer "page_number", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "document_id"], name: "index_document_pages_on_account_id_and_document_id"
    t.index ["account_id"], name: "index_document_pages_on_account_id"
    t.index ["document_id", "page_number"], name: "index_document_pages_on_document_id_and_page_number", unique: true
    t.index ["document_id"], name: "index_document_pages_on_document_id"
    t.index ["status"], name: "index_document_pages_on_status"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "byte_size"
    t.string "category", default: "general", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.bigint "dependent_id", null: false
    t.text "description"
    t.string "original_filename"
    t.text "preparation_error"
    t.string "preparation_status", default: "unprepared", null: false
    t.datetime "prepared_at"
    t.jsonb "prepared_payload", default: {}, null: false
    t.string "status", default: "uploaded", null: false
    t.datetime "summarized_at"
    t.jsonb "summary", default: {}, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["account_id", "category"], name: "index_documents_on_account_id_and_category"
    t.index ["account_id", "created_at"], name: "index_documents_on_account_id_and_created_at"
    t.index ["account_id", "status"], name: "index_documents_on_account_id_and_status"
    t.index ["account_id"], name: "index_documents_on_account_id"
    t.index ["dependent_id", "created_at"], name: "index_documents_on_dependent_id_and_created_at"
    t.index ["dependent_id"], name: "index_documents_on_dependent_id"
    t.index ["preparation_status"], name: "index_documents_on_preparation_status"
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

  create_table "timeline_events", force: :cascade do |t|
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.string "date_precision", null: false
    t.string "date_source", null: false
    t.text "description", null: false
    t.bigint "document_chunk_id", null: false
    t.date "ended_on"
    t.string "event_type", null: false
    t.jsonb "metadata", default: {}, null: false
    t.date "occurred_on"
    t.text "source_quote", null: false
    t.date "started_on"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["date_source", "date_precision"], name: "index_timeline_events_on_date_source_and_date_precision"
    t.index ["document_chunk_id", "content_hash"], name: "index_timeline_events_on_document_chunk_id_and_content_hash", unique: true
    t.index ["document_chunk_id"], name: "index_timeline_events_on_document_chunk_id"
    t.index ["event_type", "occurred_on"], name: "index_timeline_events_on_event_type_and_occurred_on"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "account_memberships", "accounts"
  add_foreign_key "account_memberships", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_types", "llms"
  add_foreign_key "care_team_memberships", "accounts"
  add_foreign_key "care_team_memberships", "dependents"
  add_foreign_key "care_team_memberships", "users"
  add_foreign_key "care_team_memberships", "users", column: "invited_by_id"
  add_foreign_key "dependents", "accounts"
  add_foreign_key "document_chunks", "accounts"
  add_foreign_key "document_chunks", "document_pages"
  add_foreign_key "document_chunks", "documents"
  add_foreign_key "document_embeddings", "document_chunks"
  add_foreign_key "document_pages", "accounts"
  add_foreign_key "document_pages", "documents"
  add_foreign_key "documents", "accounts"
  add_foreign_key "documents", "dependents"
  add_foreign_key "documents", "users"
  add_foreign_key "pipeline_activities", "pipeline_runs"
  add_foreign_key "pipeline_logs", "pipeline_runs"
  add_foreign_key "pipeline_runs", "users"
  add_foreign_key "prompts", "agent_types"
  add_foreign_key "timeline_events", "document_chunks"
end
