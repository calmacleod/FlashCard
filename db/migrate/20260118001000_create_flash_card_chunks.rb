class CreateFlashCardChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :flash_card_chunks do |t|
      t.references :flash_card_request, null: false, foreign_key: true
      t.integer :index, null: false
      t.text :path_json
      t.string :title
      t.text :content_text, null: false
      t.boolean :approved, null: false, default: false

      t.timestamps
    end

    add_index :flash_card_chunks, [:flash_card_request_id, :index], unique: true
    add_index :flash_card_chunks, [:flash_card_request_id, :approved]
  end
end
