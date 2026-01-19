class AddRefinementToFlashCards < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_cards, :status, :string, null: false, default: "kept"
    add_column :flash_cards, :refined_front, :string
    add_column :flash_cards, :refined_back, :text
    add_column :flash_cards, :refinement_reason, :text

    add_index :flash_cards, :status
  end
end
