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

ActiveRecord::Schema[8.1].define(version: 2026_01_18_001100) do
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

  add_foreign_key "flash_card_chunks", "flash_card_requests"
  add_foreign_key "flash_cards", "flash_card_requests"
end
