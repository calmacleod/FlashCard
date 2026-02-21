class RuleAgentConversation < ApplicationRecord
  serialize :messages, coder: JSON

  def messages
    super || []
  end

  def tokens
    { "input" => tokens_input.to_i, "output" => tokens_output.to_i }
  end

  def add_turn(user_input:, assistant_content:, input_tokens:, output_tokens:)
    self.messages = messages + [
      { "role" => "user",      "content" => user_input },
      { "role" => "assistant", "content" => assistant_content }
    ]
    self.tokens_input  = tokens_input.to_i  + input_tokens.to_i
    self.tokens_output = tokens_output.to_i + output_tokens.to_i
    save!
  end
end
