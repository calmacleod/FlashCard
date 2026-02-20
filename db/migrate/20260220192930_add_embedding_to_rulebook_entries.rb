class AddEmbeddingToRulebookEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :rulebook_entries, :embedding, :binary
  end
end
