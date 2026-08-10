class CreateApplicationSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :application_settings do |t|
      t.string :key, null: false
      t.json :value, null: false, default: {}

      t.timestamps
    end

    add_index :application_settings, :key, unique: true
  end
end
