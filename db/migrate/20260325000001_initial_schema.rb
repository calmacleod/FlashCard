class InitialSchema < ActiveRecord::Migration[8.0]
  def up
    # Schema is managed via db/schema.rb.
    # New environments should be set up with: bin/rails db:setup
    # This migration exists only to establish a clean history baseline.
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
