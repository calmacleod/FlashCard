class AddFlashcardPersonaToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :flashcard_persona, :string, null: false, default: "generalist"
  end
end
