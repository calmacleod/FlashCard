class AddDetailLevelToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :detail_level, :string, null: false, default: "medium"
  end
end
