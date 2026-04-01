class AddProcessingProgressToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :processing_progress, :text
  end
end
