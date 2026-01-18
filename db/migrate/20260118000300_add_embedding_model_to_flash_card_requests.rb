class AddEmbeddingModelToFlashCardRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :flash_card_requests, :embedding_model, :string, null: false, default: "nomic-embed-text"
  end
end
