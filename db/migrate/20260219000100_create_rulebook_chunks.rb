class CreateRulebookChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :rulebook_chunks do |t|
      t.string  :pdf_path,    null: false
      t.integer :chunk_index, null: false
      t.text    :chunk_text,  null: false
      t.text    :units_json
      t.string  :status,      null: false, default: "pending"

      t.timestamps
    end

    add_index :rulebook_chunks, [ :pdf_path, :chunk_index ], unique: true
    add_index :rulebook_chunks, [ :pdf_path, :status ]
  end
end
