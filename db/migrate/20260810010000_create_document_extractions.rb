class CreateDocumentExtractions < ActiveRecord::Migration[8.1]
  def change
    create_table :document_extractions do |t|
      t.references :document, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.json :schema_snapshot, null: false
      t.json :result
      t.json :progress, null: false, default: {}
      t.string :model_key, null: false
      t.json :thinking, null: false, default: {}
      t.text :error

      t.timestamps
    end

    add_index :document_extractions, [ :document_id, :created_at ]
  end
end
