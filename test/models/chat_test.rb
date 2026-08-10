require "test_helper"

class ChatTest < ActiveSupport::TestCase
  test "token totals keep normalized cache buckets separate" do
    chat = Chat.create!(session_token: SecureRandom.hex(12))
    chat.messages.create!(
      role: :assistant,
      input_tokens: 10,
      cached_tokens: 20,
      cache_creation_tokens: 30,
      output_tokens: 40
    )

    assert_equal(
      { "input" => 10, "cache_read" => 20, "cache_write" => 30, "output" => 40 },
      chat.tokens
    )
  end
end
