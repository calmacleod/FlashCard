class CreateRuleAgentConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :rule_agent_conversations do |t|
      t.string :session_token, null: false, index: { unique: true }
      t.string :source_csv
      t.text :messages
      t.integer :tokens_input
      t.integer :tokens_output

      t.timestamps
    end
  end
end
