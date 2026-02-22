class DropRuleAgentConversations < ActiveRecord::Migration[8.1]
  def change
    drop_table :rule_agent_conversations
  end
end
