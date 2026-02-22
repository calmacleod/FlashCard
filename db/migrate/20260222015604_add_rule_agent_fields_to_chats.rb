class AddRuleAgentFieldsToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :session_token, :string
    add_index :chats, :session_token, unique: true
    add_column :chats, :source_csv, :string
  end
end
