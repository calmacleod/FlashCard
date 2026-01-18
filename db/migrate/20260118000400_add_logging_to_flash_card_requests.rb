class AddLoggingToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :current_step, :string
    add_column :flash_card_requests, :log_text, :text
  end
end
