class AddLlmSettingsAndSchemaStatusToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :llm_settings, :json, default: {}, null: false
    add_column :documents, :schema_generation_status, :string
    add_column :documents, :schema_generation_error, :text
  end
end
