class RuleAgentController < ApplicationController
  BROWSER_COOKIE = :rule_agent_browser
  SESSION_COOKIE = :rule_agent_token

  def index
    @sources = RulebookEntry.distinct.pluck(:source_csv).sort

    if params[:chat].present?
      target = Chat.find_by(session_token: params[:chat], browser_token: browser_token)
      if target
        set_session_cookie(target.session_token)
        @chat = target
      end
    end

    @chat ||= find_or_create_chat
    @source = @chat.source_csv || @sources.first
    current_model = current_model_key(@chat)
    @agent_models = LlmModelCatalog.options(capability: :function_calling, current: current_model)
    @selected_model = @agent_models.find { |model| model.key == current_model }&.key ||
      LlmModelCatalog.default(:agent) || @agent_models.first&.key
    @thinking_configurations = LlmModelCatalog.configuration_map(@agent_models)

    user_msgs      = @chat.messages.where(role: :user)
    assistant_msgs = @chat.messages.where(role: :assistant).where.not(content: [ nil, "" ])
    @messages = user_msgs.or(assistant_msgs).order(:created_at)
    @tokens   = @chat.tokens
    @processing = @chat.messages.order(:created_at).last&.role.to_s == "user"

    @past_chats = Chat.where(browser_token: browser_token)
                      .where.not(id: @chat.id)
                      .order(updated_at: :desc)
                      .limit(30)
  end

  def create_message
    source = params[:source_csv]
    input  = params[:message].to_s.strip
    return head :bad_request if input.blank?

    chat = find_or_create_chat
    entry = LlmModelCatalog.find!(params[:model].presence || LlmModelCatalog.default(:agent), capability: :function_calling)
    chat.with_model(entry.model_id, provider: entry.provider.to_sym) if current_model_key(chat) != entry.key
    chat.update!(source_csv: source)

    chat.update!(title: input.truncate(60)) unless chat.title.present?

    chat.add_message(role: :user, content: input)
    @user_message_record = chat.messages.where(role: :user).order(:created_at).last

    base_url = "#{request.scheme}://#{request.host_with_port}"
    thinking = LlmModelCatalog.thinking_params(
      entry, effort: params[:thinking_effort], budget: params[:thinking_budget]
    )
    RuleAgentJob.perform_later(chat.id, source, base_url, thinking)

    @chat_id = chat.id

    respond_to do |format|
      format.turbo_stream
    end
  end

  def new_chat
    cookies.delete(SESSION_COOKIE)
    redirect_to rule_agent_path
  end

  def clear
    find_or_create_chat.destroy
    cookies.delete(SESSION_COOKIE)
    redirect_to rule_agent_path
  end

  def self.format_reference_links_for(content)
    content.gsub(/(?<!\()https?:\/\/\S+\/rule_search\/search\S*/) do |url|
      next url if content.match?(/\[[^\]]+\]\(#{Regexp.escape(url)}\)/)

      params = Rack::Utils.parse_query(URI.parse(url).query)
      parts  = [ params["rule_number"], params["section"], params["article"] ].compact.reject(&:empty?)
      label  = parts.any? ? parts.join(" › ") : "Rule Reference"
      "[#{label}](#{url})"
    end
  end

  private

  def browser_token
    @browser_token ||= begin
      existing = cookies[BROWSER_COOKIE].presence
      if existing
        existing
      else
        token = SecureRandom.hex(16)
        cookies[BROWSER_COOKIE] = { value: token, expires: 5.years, same_site: :lax }
        token
      end
    end
  end

  def find_or_create_chat
    token = cookies[SESSION_COOKIE].presence || SecureRandom.hex(16)
    set_session_cookie(token) unless cookies[SESSION_COOKIE]
    entry = LlmModelCatalog.find!(params[:model].presence || LlmModelCatalog.default(:agent), capability: :function_calling)
    Chat.find_or_create_by!(session_token: token) do |c|
      c.model         = Model.find_by!(provider: entry.provider, model_id: entry.model_id)
      c.browser_token = browser_token
    end
  end

  def current_model_key(chat)
    model = chat.model_association
    "#{model.provider}:#{model.model_id}" if model
  end

  def set_session_cookie(token)
    cookies[SESSION_COOKIE] = { value: token, expires: 1.year, same_site: :lax }
  end
end
