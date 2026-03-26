class DropFlashCardTables < ActiveRecord::Migration[8.0]
  def up
    drop_table :flash_card_chunks
    drop_table :flash_cards
    drop_table :flash_card_requests
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
