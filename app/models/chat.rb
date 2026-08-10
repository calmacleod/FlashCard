class Chat < ApplicationRecord
  acts_as_chat messages_foreign_key: :chat_id

  validates :session_token, presence: true, uniqueness: true

  def tokens
    msgs = messages.where(role: :assistant)
    {
      "input"       => msgs.sum(:input_tokens),
      "cache_read"  => msgs.sum(:cached_tokens),
      "cache_write" => msgs.sum(:cache_creation_tokens),
      "output"      => msgs.sum(:output_tokens)
    }
  end
end
