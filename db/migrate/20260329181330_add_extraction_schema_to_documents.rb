class AddExtractionSchemaToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :extraction_schema, :text
  end
end
