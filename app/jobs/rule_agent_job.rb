class RuleAgentJob < ApplicationJob
  queue_as :default

  THINKING_BROADCAST_EVERY = 200 # characters
  CONTENT_BROADCAST_EVERY  = 100 # characters

  def perform(chat_id, source_csv, base_url)
    agent = RuleAgent.find(chat_id, source_csv: source_csv, base_url: base_url)

    # Stream thinking and content tokens to the client as they arrive.
    accumulated_thinking        = +""
    accumulated_content         = +""
    last_thinking_broadcast_at  = 0
    last_content_broadcast_at   = 0

    agent.complete do |chunk|
      if chunk.thinking&.text.present?
        accumulated_thinking << chunk.thinking.text

        if accumulated_thinking.length - last_thinking_broadcast_at >= THINKING_BROADCAST_EVERY
          last_thinking_broadcast_at = accumulated_thinking.length
          Turbo::StreamsChannel.broadcast_replace_to(
            "rule_agent_#{chat_id}",
            target: "thinking_#{chat_id}",
            partial: "rule_agent/thinking_stream",
            locals: { chat_id: chat_id, thinking_text: accumulated_thinking }
          )
        end
      elsif chunk.content.present?
        accumulated_content << chunk.content

        if accumulated_content.length - last_content_broadcast_at >= CONTENT_BROADCAST_EVERY
          last_content_broadcast_at = accumulated_content.length
          Turbo::StreamsChannel.broadcast_replace_to(
            "rule_agent_#{chat_id}",
            target: "thinking_#{chat_id}",
            partial: "rule_agent/content_stream",
            locals: { chat_id: chat_id, thinking_text: accumulated_thinking, content_text: accumulated_content }
          )
        end
      end
    end

    chat    = Chat.find(chat_id)
    last_msg = chat.messages.where(role: :assistant).order(:created_at).last
    return unless last_msg

    formatted = RuleAgentController.format_reference_links_for(last_msg.content.to_s)
    last_msg.update_column(:content, formatted) if formatted != last_msg.content

    Turbo::StreamsChannel.broadcast_replace_to(
      "rule_agent_#{chat_id}",
      target: "thinking_#{chat_id}",
      partial: "rule_agent/message",
      locals: { message: last_msg, chat_id: chat_id }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "rule_agent_#{chat_id}",
      target: "token-usage",
      partial: "rule_agent/token_usage",
      locals: { tokens: chat.tokens }
    )
  rescue RubyLLM::ServiceUnavailableError
    Turbo::StreamsChannel.broadcast_replace_to(
      "rule_agent_#{chat_id}",
      target: "thinking_#{chat_id}",
      partial: "rule_agent/error_message",
      locals: { error_message: "The model is currently experiencing high demand. Please try again in a moment." }
    )
  end
end
