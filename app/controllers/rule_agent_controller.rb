class RuleAgentController < ApplicationController
  def index
    @sources      = RulebookEntry.distinct.pluck(:source_csv).sort
    @conversation = find_or_create_conversation
    @source       = @conversation.source_csv || @sources.first
    @messages     = @conversation.messages
    @tokens       = @conversation.tokens
  end

  def create_message
    source = params[:source_csv]
    input  = params[:message].to_s.strip
    return head :bad_request if input.blank?

    conversation = find_or_create_conversation
    conversation.update!(source_csv: source)

    chat = RubyLLM.chat(model: params[:model].presence || "gemini-2.5-flash-lite")
                  .with_instructions(RuleAgent::SYSTEM_PROMPT)
                  .with_tool(RuleSearchTool.new(source_csv: source))
                  .with_tool(RuleDefinitionLookupTool.new(source_csv: source))

    conversation.messages.each do |msg|
      chat.messages << RubyLLM::Message.new(role: msg["role"].to_sym, content: msg["content"])
    end

    response = chat.ask(input)

    if response.content.blank?
      response = chat.ask("Please summarize the results you just retrieved from the tools and answer my question.")
    end

    assistant_content = response.content.presence || "(The model returned an empty response. Please try again.)"

    conversation.add_turn(
      user_input:        input,
      assistant_content: assistant_content,
      input_tokens:      response.input_tokens,
      output_tokens:     response.output_tokens
    )

    @user_message      = input
    @assistant_message = assistant_content
    @tokens            = conversation.tokens

    respond_to do |format|
      format.turbo_stream
    end
  rescue RubyLLM::ServiceUnavailableError
    @error_message = "The model is currently experiencing high demand. Please try again in a moment."
    @user_message  = input
    respond_to do |format|
      format.turbo_stream { render :error }
    end
  end

  def clear
    find_or_create_conversation.destroy
    cookies.delete(:rule_agent_token)
    redirect_to rule_agent_path
  end

  private

  def find_or_create_conversation
    token = cookies[:rule_agent_token].presence || SecureRandom.hex(16)
    cookies[:rule_agent_token] = { value: token, expires: 1.year, same_site: :lax } unless cookies[:rule_agent_token]
    RuleAgentConversation.find_or_create_by!(session_token: token)
  end
end
