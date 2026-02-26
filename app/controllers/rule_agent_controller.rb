class RuleAgentController < ApplicationController
  def index
    @sources  = RulebookEntry.distinct.pluck(:source_csv).sort
    @chat     = find_or_create_chat
    @source   = @chat.source_csv || @sources.first
    @messages = @chat.messages.where(role: %w[user assistant]).order(:created_at)
    @tokens   = @chat.tokens
  end

  def create_message
    source = params[:source_csv]
    input  = params[:message].to_s.strip
    return head :bad_request if input.blank?

    chat = find_or_create_chat
    chat.update!(source_csv: source)

    base_url = "#{request.scheme}://#{request.host_with_port}"
    agent    = RuleAgent.find(chat.id, source_csv: source, base_url: base_url)
    response = agent.ask(input)

    if response.content.blank?
      response = agent.ask("Please summarize the results you just retrieved from the tools and answer my question.")
    end

    formatted = format_reference_links(
      response.content.presence || "(The model returned an empty response. Please try again.)"
    )

    assistant_messages = chat.messages.where(role: :assistant).order(:created_at)
    last_message = assistant_messages.last
    # Destroy intermediate assistant messages that have no text AND no tool calls
    assistant_messages.where.not(id: last_message.id).each do |m|
      m.destroy if m.content.blank? && m.tool_calls.empty?
    end
    last_message&.update!(content: formatted)

    @user_message             = input
    @assistant_message        = formatted
    @assistant_message_record = last_message
    @tokens                   = chat.tokens

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
    find_or_create_chat.destroy
    cookies.delete(:rule_agent_token)
    redirect_to rule_agent_path
  end

  private

  # If the LLM includes a bare rule_search URL instead of a markdown link,
  # wrap it in [label](url) syntax so Redcarpet renders it as a clickable link.
  def format_reference_links(content)
    content.gsub(/(?<!\()https?:\/\/\S+\/rule_search\/search\S*/) do |url|
      next url if content.match?(/\[[^\]]+\]\(#{Regexp.escape(url)}\)/)

      params = Rack::Utils.parse_query(URI.parse(url).query)
      parts  = [ params["rule_number"], params["section"], params["article"] ].compact.reject(&:empty?)
      label  = parts.any? ? parts.join(" › ") : "Rule Reference"
      "[#{label}](#{url})"
    end
  end

  def find_or_create_chat
    token = cookies[:rule_agent_token].presence || SecureRandom.hex(16)
    cookies[:rule_agent_token] = { value: token, expires: 1.year, same_site: :lax } unless cookies[:rule_agent_token]
    model_name = params[:model].presence || "gemini-2.5-flash-lite"
    Chat.find_or_create_by!(session_token: token) do |c|
      c.model = Model.find_by(model_id: model_name)
    end
  end
end
