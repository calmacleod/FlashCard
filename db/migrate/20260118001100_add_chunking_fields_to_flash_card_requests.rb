class AddChunkingFieldsToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :chunking_prompt, :text
    add_column :flash_card_requests, :chunking_status, :string, null: false, default: "pending"
  end
end
