class AddRefinementPromptToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :refinement_prompt, :text
  end
end
