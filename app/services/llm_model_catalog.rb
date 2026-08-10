class LlmModelCatalog
  Entry = Data.define(:key, :model_id, :provider, :name, :capabilities, :created_at) do
    PROVIDER_LABELS = { "openai" => "OpenAI", "gemini" => "Gemini" }.freeze

    def provider_label = PROVIDER_LABELS.fetch(provider, provider.titleize)
    def label = "#{name} (#{provider_label})"
    def reasoning? = capabilities.include?("reasoning")
  end

  PROVIDERS = %w[openai gemini].freeze
  DOCUMENT_WORKFLOW_CAPABILITIES = %i[structured_output function_calling].freeze
  EXCLUDED_ID_PARTS = %w[
    audio realtime image search transcribe transcription tts embedding reranker codex
    live omni robotics customtools
  ].freeze
  RECENT_RELEASE_CUTOFF = 1.year.ago.beginning_of_day.freeze
  EFFORTS = {
    "openai" => %w[minimal low medium high xhigh],
    "openai_5_6" => %w[none low medium high xhigh max],
    "gemini_flash" => %w[minimal low medium high],
    "gemini_pro" => %w[low high]
  }.freeze
  DEFAULTS = {
    agent: "openai:gpt-5.6-luna",
    schema: "openai:gpt-5.6-luna",
    extraction: "gemini:gemini-3.6-flash",
    flashcards: "openai:gpt-5.6-luna"
  }.freeze

  class << self
    def options(capability:, current: nil)
      required_capabilities = Array(capability).map(&:to_s)
      entries = Model.where(provider: PROVIDERS).order(model_created_at: :desc, name: :asc).filter_map do |model|
        next unless required_capabilities.all? { |required| Array(model.capabilities).include?(required) }
        next unless selectable?(model)

        build_entry(model)
      end
      entries = entries.group_by(&:provider).flat_map { |_provider, models| models.first(12) }
      current_entry = find(current, capability:) if current.present?
      entries << current_entry if current_entry && entries.none? { |entry| entry.key == current_entry.key }
      entries.sort_by { |entry| [ entry.provider, -(entry.created_at&.to_i || 0), entry.name ] }
    end

    def find(key, capability: nil)
      provider, model_id = key.to_s.split(":", 2)
      return if provider.blank? || model_id.blank? || !PROVIDERS.include?(provider)

      model = Model.find_by(provider:, model_id:)
      return unless model
      required_capabilities = Array(capability).map(&:to_s)
      return unless required_capabilities.all? { |required| Array(model.capabilities).include?(required) }

      build_entry(model)
    end

    def find!(key, capability: nil)
      find(key, capability:) || raise(ArgumentError, "Unsupported model selection")
    end

    def default(context)
      context = context.to_sym
      configured = ApplicationSetting.value_for("workflow_defaults", default: {})
      preferred = configured.fetch(context.to_s, DEFAULTS.fetch(context))
      capability = required_capability(context)
      find(preferred, capability:) ? preferred : options(capability:).first&.key
    end

    def update_defaults!(raw_defaults)
      submitted = raw_defaults.to_h.stringify_keys
      defaults = DEFAULTS.keys.to_h do |context|
        key = submitted[context.to_s].presence || default(context)
        entry = find!(key, capability: required_capability(context))
        [ context.to_s, entry.key ]
      end
      ApplicationSetting.write("workflow_defaults", defaults)
    end

    def thinking_configuration(entry_or_key)
      entry = entry_or_key.is_a?(Entry) ? entry_or_key : find(entry_or_key)
      return { mode: "none", efforts: [] } unless entry&.reasoning?

      if entry.provider == "gemini" && entry.model_id.start_with?("gemini-2.5")
        { mode: "budget", efforts: [] }
      elsif entry.provider == "gemini"
        family = entry.model_id.include?("pro") ? "gemini_pro" : "gemini_flash"
        { mode: "effort", efforts: EFFORTS.fetch(family) }
      elsif entry.provider == "openai"
        family = entry.model_id.start_with?("gpt-5.6") ? "openai_5_6" : "openai"
        { mode: "effort", efforts: EFFORTS.fetch(family) }
      else
        { mode: "none", efforts: [] }
      end
    end

    def thinking_params(entry_or_key, effort: nil, budget: nil)
      config = thinking_configuration(entry_or_key)
      case config[:mode]
      when "effort"
        value = effort.to_s
        config[:efforts].include?(value) ? { effort: value } : {}
      when "budget"
        value = Integer(budget, exception: false)
        value && value.between?(0, 65_536) ? { budget: value } : {}
      else
        {}
      end
    end

    def tool_thinking_configuration(entry_or_key)
      entry = entry_or_key.is_a?(Entry) ? entry_or_key : find(entry_or_key)
      config = thinking_configuration(entry)
      return config unless openai_chat_tool_reasoning_conflict?(entry)

      {
        mode: "effort",
        efforts: [ "none" ],
        hint: "RubyLLM uses Chat Completions for OpenAI; tool workflows require reasoning effort none."
      }
    end

    def tool_thinking_params(entry_or_key, effort: nil, budget: nil)
      entry = entry_or_key.is_a?(Entry) ? entry_or_key : find(entry_or_key)
      normalize_tool_thinking(entry, thinking_params(entry, effort:, budget:))
    end

    def normalize_tool_thinking(entry_or_key, thinking)
      entry = entry_or_key.is_a?(Entry) ? entry_or_key : find(entry_or_key)
      params = thinking.to_h.symbolize_keys
      return params unless openai_chat_tool_reasoning_conflict?(entry)
      return params if params[:effort].blank? || params[:effort] == "none"

      params.merge(effort: "none")
    end

    def configuration_map(entries, tools: false)
      entries.to_h do |entry|
        config = tools ? tool_thinking_configuration(entry) : thinking_configuration(entry)
        [ entry.key, config ]
      end
    end

    def required_capability(context)
      context.to_sym == :agent ? :function_calling : DOCUMENT_WORKFLOW_CAPABILITIES
    end

    private

    def build_entry(model)
      Entry.new(
        key: "#{model.provider}:#{model.model_id}", model_id: model.model_id,
        provider: model.provider, name: model.name, capabilities: Array(model.capabilities),
        created_at: model.model_created_at
      )
    end

    def snapshot?(model_id) = model_id.match?(/-\d{4}-\d{2}-\d{2}\z/)

    def selectable?(model)
      return false if model.model_created_at.blank? || model.model_created_at < RECENT_RELEASE_CUTOFF
      return false if snapshot?(model.model_id) || excluded?(model.model_id)

      case model.provider
      when "openai" then model.model_id.match?(/\Agpt-5\.(?:4|5|6)(?:\z|-)/)
      when "gemini" then model.model_id.match?(/\Agemini-(?:3\.|flash)/)
      else false
      end
    end

    def excluded?(model_id)
      normalized = model_id.downcase
      normalized.start_with?("bge-") || EXCLUDED_ID_PARTS.any? { |part| normalized.include?(part) }
    end

    def openai_chat_tool_reasoning_conflict?(entry)
      entry&.provider == "openai" && entry.model_id.start_with?("gpt-5.6")
    end
  end
end
