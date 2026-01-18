class AddJobTrackingToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    change_column_null :flash_card_requests, :response_text, true

    add_column :flash_card_requests, :status, :string, null: false, default: "queued"
    add_column :flash_card_requests, :progress, :integer, null: false, default: 0
    add_column :flash_card_requests, :pdf_path, :string
    add_column :flash_card_requests, :vector_path, :string
    add_column :flash_card_requests, :error_message, :text
  end
end
