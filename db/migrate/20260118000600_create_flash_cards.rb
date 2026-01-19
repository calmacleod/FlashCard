class CreateFlashCards < ActiveRecord::Migration[8.1]
  def change
    create_table :flash_cards do |t|
      t.references :flash_card_request, null: false, foreign_key: true
      t.integer :chunk_index, null: false, default: 0
      t.string :front, null: false
      t.text :back, null: false

      t.timestamps
    end

    add_index :flash_cards, [:flash_card_request_id, :chunk_index]
  end
end
