class LlmModelCatalog
  Entry = Data.define(:key, :model_id, :provider, :name, :capabilities, :created_at) do
    def label = "#{name} (#{provider.titleize})"
    def reasoning? = capabilities.include?("reasoning")
  end

  PROVIDERS = %w[openai gemini ollama].freeze
  EXCLUDED_ID_PARTS = %w[audio realtime image search transcribe transcription tts embedding reranker codex].freeze
  EFFORTS = {
    "openai" => %w[minimal low medium high xhigh],
    "gemini_flash" => %w[minimal low medium high],
    "gemini_pro" => %w[low high],
    "anthropic" => %w[low medium high]
  }.freeze
  DEFAULTS = {
    agent: "openai:gpt-5.4-nano",
    schema: "openai:gpt-5.4-nano",
    extraction: "gemini:gemini-3-flash-preview",
    flashcards: "openai:gpt-5.4-nano"
  }.freeze
  PINNED = %w[
    gemini:gemini-2.5-flash gemini:gemini-2.5-flash-lite
    openai:gpt-5.4-nano openai:gpt-5.4-mini
  ].freeze

  class << self
    def options(capability:, current: nil)
      entries = Model.where(provider: PROVIDERS).order(model_created_at: :desc, name: :asc).filter_map do |model|
        next unless Array(model.capabilities).include?(capability.to_s)
        next if snapshot?(model.model_id) || excluded?(model.model_id)

        build_entry(model)
      end
      entries = entries.group_by(&:provider).flat_map { |_provider, models| models.first(8) }
      PINNED.filter_map { |key| find(key, capability:) }.each do |entry|
        entries << entry unless entries.any? { |existing| existing.key == entry.key }
      end
      current_entry = find(current, capability:) if current.present?
      entries << current_entry if current_entry && entries.none? { |entry| entry.key == current_entry.key }
      entries.sort_by { |entry| [ entry.provider, -(entry.created_at&.to_i || 0), entry.name ] }
    end

    def find(key, capability: nil)
      provider, model_id = key.to_s.split(":", 2)
      return if provider.blank? || model_id.blank? || !PROVIDERS.include?(provider)

      model = Model.find_by(provider:, model_id:)
      return unless model
      return if capability && !Array(model.capabilities).include?(capability.to_s)

      build_entry(model)
    end

    def find!(key, capability: nil)
      find(key, capability:) || raise(ArgumentError, "Unsupported model selection")
    end

    def default(context)
      preferred = DEFAULTS.fetch(context.to_sym)
      find(preferred) ? preferred : options(capability: required_capability(context)).first&.key
    end

    def thinking_configuration(entry_or_key)
      entry = entry_or_key.is_a?(Entry) ? entry_or_key : find(entry_or_key)
      return { mode: "none", efforts: [] } unless entry&.reasoning?

      if entry.provider == "gemini" && entry.model_id.start_with?("gemini-2.5")
        { mode: "budget", efforts: [] }
      elsif entry.provider == "gemini"
        family = entry.model_id.include?("pro") ? "gemini_pro" : "gemini_flash"
        { mode: "effort", efforts: EFFORTS.fetch(family) }
      elsif entry.provider == "anthropic" && entry.model_id.match?(/claude-(?:opus|sonnet)-4-[6-9]/)
        { mode: "effort", efforts: EFFORTS.fetch("anthropic") }
      elsif entry.provider == "anthropic"
        { mode: "budget", efforts: [] }
      elsif entry.provider == "openai"
        { mode: "effort", efforts: EFFORTS.fetch("openai") }
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

    def configuration_map(entries)
      entries.to_h { |entry| [ entry.key, thinking_configuration(entry) ] }
    end

    private

    def required_capability(context)
      context.to_sym == :agent ? :function_calling : :structured_output
    end

    def build_entry(model)
      Entry.new(
        key: "#{model.provider}:#{model.model_id}", model_id: model.model_id,
        provider: model.provider, name: model.name, capabilities: Array(model.capabilities),
        created_at: model.model_created_at
      )
    end

    def snapshot?(model_id) = model_id.match?(/-\d{4}-\d{2}-\d{2}\z/)
    def excluded?(model_id)
      normalized = model_id.downcase
      normalized.start_with?("bge-") || EXCLUDED_ID_PARTS.any? { |part| normalized.include?(part) }
    end
  end
end
