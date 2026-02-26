class RuleAgentJob < ApplicationJob
  queue_as :default

  THINKING_BROADCAST_EVERY = 200 # characters

  def perform(chat_id, source_csv, base_url)
    agent = RuleAgent.find(chat_id, source_csv: source_csv, base_url: base_url)

    # Broadcast final assistant message (with stored thinking_text) as soon as
    # it is saved, before the link-formatting pass below.
    agent.on_end_message do |msg|
      next unless msg.role.to_s == "assistant" && msg.content.present?

      ar_msg = Chat.find(chat_id).messages.where(role: :assistant).order(:created_at).last
      next unless ar_msg

      Turbo::StreamsChannel.broadcast_replace_to(
        "rule_agent_#{chat_id}",
        target: "thinking_#{chat_id}",
        partial: "rule_agent/message",
        locals: { message: ar_msg }
      )
    end

    # Stream thinking tokens to the client as they arrive.
    accumulated_thinking = +""
    last_broadcast_at     = 0

    agent.complete do |chunk|
      next unless chunk.thinking&.text.present?

      accumulated_thinking << chunk.thinking.text

      if accumulated_thinking.length - last_broadcast_at >= THINKING_BROADCAST_EVERY
        last_broadcast_at = accumulated_thinking.length
        Turbo::StreamsChannel.broadcast_replace_to(
          "rule_agent_#{chat_id}",
          target: "thinking_#{chat_id}",
          partial: "rule_agent/thinking_stream",
          locals: { chat_id: chat_id, thinking_text: accumulated_thinking }
        )
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
      locals: { message: last_msg }
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
