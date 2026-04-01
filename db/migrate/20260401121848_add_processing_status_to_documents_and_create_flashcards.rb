class AddProcessingStatusToDocumentsAndCreateFlashcards < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :processing_status, :string
    add_column :documents, :processing_error, :text

    create_table :flashcards do |t|
      t.references :document, null: false, foreign_key: true
      t.text :reference
      t.text :front, null: false
      t.text :back, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :flashcards, [:document_id, :position]
  end
end
