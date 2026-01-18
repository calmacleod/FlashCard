class AddPromptTextToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :prompt_text, :text
  end
end
