class AddBrowserTokenAndTitleToChats < ActiveRecord::Migration[8.1]
  def change
    add_column :chats, :browser_token, :string
    add_index  :chats, :browser_token
    add_column :chats, :title, :string
  end
end
