class CreateFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :flash_card_requests do |t|
      t.string :pdf_filename, null: false
      t.string :model, null: false
      t.text :notes
      t.text :guidance
      t.text :response_text, null: false

      t.timestamps
    end
  end
end
