class CreateRulebookEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :rulebook_entries do |t|
      t.string  :source_csv,  null: false
      t.integer :entry_index, null: false
      t.string  :rule_number
      t.string  :section
      t.string  :article
      t.text    :text,        null: false
      t.timestamps
    end

    add_index :rulebook_entries, :source_csv
    add_index :rulebook_entries, [ :source_csv, :entry_index ], unique: true
  end
end
