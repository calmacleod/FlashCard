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

ActiveRecord::Schema[8.1].define(version: 2026_02_22_015610) do
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

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "model_id"
    t.string "session_token"
    t.string "source_csv"
    t.datetime "updated_at", null: false
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["session_token"], name: "index_chats_on_session_token", unique: true
  end

  create_table "flash_card_chunks", force: :cascade do |t|
    t.boolean "approved", default: false, null: false
    t.text "content_text", null: false
    t.datetime "created_at", null: false
    t.integer "flash_card_request_id", null: false
    t.integer "index", null: false
    t.text "path_json"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["flash_card_request_id", "approved"], name: "index_flash_card_chunks_on_flash_card_request_id_and_approved"
    t.index ["flash_card_request_id", "index"], name: "index_flash_card_chunks_on_flash_card_request_id_and_index", unique: true
    t.index ["flash_card_request_id"], name: "index_flash_card_chunks_on_flash_card_request_id"
  end

  create_table "flash_card_requests", force: :cascade do |t|
    t.text "chunking_prompt"
    t.string "chunking_status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.string "current_step"
    t.string "detail_level", default: "medium", null: false
    t.string "embedding_model", default: "nomic-embed-text", null: false
    t.text "error_message"
    t.text "guidance"
    t.text "log_text"
    t.string "model", null: false
    t.text "notes"
    t.string "pdf_filename", null: false
    t.string "pdf_path"
    t.integer "progress", default: 0, null: false
    t.text "prompt_text"
    t.text "refinement_prompt"
    t.text "response_text"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.string "vector_path"
  end

  create_table "flash_cards", force: :cascade do |t|
    t.text "back", null: false
    t.integer "chunk_index", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "flash_card_request_id", null: false
    t.string "front", null: false
    t.text "refined_back"
    t.string "refined_front"
    t.text "refinement_reason"
    t.string "status", default: "kept", null: false
    t.datetime "updated_at", null: false
    t.index ["flash_card_request_id", "chunk_index"], name: "index_flash_cards_on_flash_card_request_id_and_chunk_index"
    t.index ["flash_card_request_id"], name: "index_flash_cards_on_flash_card_request_id"
    t.index ["status"], name: "index_flash_cards_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.integer "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.integer "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "rulebook_chunks", force: :cascade do |t|
    t.integer "chunk_index", null: false
    t.text "chunk_text", null: false
    t.datetime "created_at", null: false
    t.string "pdf_path", null: false
    t.string "status", default: "pending", null: false
    t.text "units_json"
    t.datetime "updated_at", null: false
    t.index ["pdf_path", "chunk_index"], name: "index_rulebook_chunks_on_pdf_path_and_chunk_index", unique: true
    t.index ["pdf_path", "status"], name: "index_rulebook_chunks_on_pdf_path_and_status"
  end

  create_table "rulebook_entries", force: :cascade do |t|
    t.string "article"
    t.datetime "created_at", null: false
    t.binary "embedding"
    t.integer "entry_index", null: false
    t.string "rule_number"
    t.string "section"
    t.string "source_csv", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.index ["source_csv", "entry_index"], name: "index_rulebook_entries_on_source_csv_and_entry_index", unique: true
    t.index ["source_csv"], name: "index_rulebook_entries_on_source_csv"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.string "name", null: false
    t.string "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chats", "models"
  add_foreign_key "flash_card_chunks", "flash_card_requests"
  add_foreign_key "flash_cards", "flash_card_requests"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "tool_calls", "messages"
end
