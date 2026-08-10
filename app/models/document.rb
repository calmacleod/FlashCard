class Document < ApplicationRecord
  has_one_attached :file
  has_many :flashcards, dependent: :destroy
  has_many :extractions, class_name: "DocumentExtraction", dependent: :destroy

  PROCESSING_STATUSES = %w[processing completed failed].freeze
  LLM_CONTEXTS = %i[schema extraction flashcards].freeze

  ALLOWED_CONTENT_TYPES = %w[application/pdf text/plain].freeze

  validates :name, presence: true
  validates :flashcard_persona, inclusion: { in: FlashcardPersona::PERSONAS.keys }
  validate :valid_extraction_schema_json

  def progress
    return {} if processing_progress.blank?
    JSON.parse(processing_progress)
  rescue JSON::ParserError
    {}
  end

  def extraction_schema_hash
    return nil if extraction_schema.blank?
    JSON.parse(extraction_schema)
  rescue JSON::ParserError
    nil
  end

  def latest_extraction
    extractions.recent_first.first
  end

  def latest_completed_extraction
    extractions.where(status: "completed").recent_first.first
  end

  def llm_setting(context)
    context = context.to_sym
    raise ArgumentError, "Unknown LLM context" unless LLM_CONTEXTS.include?(context)

    stored = llm_settings.fetch(context.to_s, {})
    stored.merge("model" => stored["model"].presence || LlmModelCatalog.default(context))
  end

  def update_llm_settings(raw_settings)
    submitted = raw_settings.to_h.stringify_keys.slice(*LLM_CONTEXTS.map(&:to_s))
    normalized = submitted.to_h do |context_name, context_settings|
      context = context_name.to_sym
      raw = context_settings.to_h.stringify_keys
      model_key = raw["model"].presence || llm_setting(context).fetch("model")
      entry = LlmModelCatalog.find!(
        model_key, capability: LlmModelCatalog.required_capability(context)
      )
      thinking = LlmModelCatalog.thinking_params(entry, effort: raw["effort"], budget: raw["budget"])
      [ context_name, { "model" => entry.key }.merge(thinking.stringify_keys) ]
    end
    self.llm_settings = llm_settings.merge(normalized)
  end
  validate :file_attached
  validate :acceptable_file_type, if: -> { file.attached? }

  private

  def valid_extraction_schema_json
    return if extraction_schema.blank?

    schema = JSON.parse(extraction_schema)
    unless schema.is_a?(Hash) && schema["type"] == "object" && schema["properties"].is_a?(Hash)
      errors.add(:extraction_schema, "must define a JSON Schema object with properties")
    end
  rescue JSON::ParserError
    errors.add(:extraction_schema, "is not valid JSON")
  end

  def file_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def acceptable_file_type
    unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
      errors.add(:file, "must be a PDF or plain text file")
    end
  end
end
