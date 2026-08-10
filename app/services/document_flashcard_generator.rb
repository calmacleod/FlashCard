class DocumentFlashcardGenerator
  Card = Data.define(:reference, :front, :back)
  MAX_SOURCE_CHARACTERS = 18_000

  class CardSchema < RubyLLM::Schema
    array :cards do
      object do
        string :reference, description: "Precise source heading, section, page, or other citation"
        string :front, description: "A clear question"
        string :back, description: "A concise answer supported by the source"
      end
    end
  end

  def self.generate(extraction, model_key:, persona_key:, thinking: {}, on_progress: nil)
    new(
      extraction, model_key:, persona_key:, thinking:, on_progress:
    ).generate
  end

  def initialize(extraction, model_key:, persona_key:, thinking: {}, on_progress: nil)
    @extraction = extraction
    @entry = LlmModelCatalog.find!(model_key, capability: :structured_output)
    @persona = FlashcardPersona.find!(persona_key)
    @thinking = thinking.symbolize_keys
    @on_progress = on_progress
  end

  def generate
    groups = source_groups
    @on_progress&.call(0, groups.length, 0)
    cards = []

    groups.each_with_index do |source, index|
      cards.concat(generate_group(source, index:, total: groups.length))
      cards = deduplicate(cards)
      @on_progress&.call(index + 1, groups.length, cards.length)
    end

    cards
  end

  private

  def generate_group(source, index:, total:)
    chat = RubyLLM.chat(model: @entry.model_id, provider: @entry.provider.to_sym)
    chat.with_thinking(**@thinking) if @thinking.any?
    response = chat.with_schema(CardSchema).ask(prompt(source, index:, total:))
    payload = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)

    Array(payload["cards"] || payload[:cards]).filter_map do |raw_card|
      raw_card = raw_card.stringify_keys
      front = raw_card["front"].to_s.strip
      back = raw_card["back"].to_s.strip
      next if front.blank? || back.blank?

      Card.new(reference: raw_card["reference"].to_s.strip, front:, back:)
    end
  end

  def prompt(source, index:, total:)
    <<~PROMPT
      You are creating study flashcards from extracted document data.

      PERSONA: #{@persona.name}
      #{@persona.instructions.strip}

      This is source group #{index + 1} of #{total}.

      RULES:
      - Use only information present in the source below. Never invent facts or citations.
      - Test one meaningful idea per card.
      - Make the front a direct question and the back a complete, concise answer.
      - Avoid duplicate, trivial, or opinion-based questions.
      - Return a JSON object containing a cards array.

      EXTRACTED SOURCE:
      #{source}
    PROMPT
  end

  def source_groups
    markdown = ExtractionMarkdownRenderer.render(
      @extraction.result, schema: @extraction.schema_snapshot
    )
    paragraphs = markdown.split(/\n{2,}/).map(&:strip).reject(&:empty?)
    groups = []
    current = +""

    paragraphs.each do |paragraph|
      slices(paragraph).each do |piece|
        if current.present? && current.length + piece.length + 2 > MAX_SOURCE_CHARACTERS
          groups << current
          current = +""
        end
        current << "\n\n" if current.present?
        current << piece
      end
    end
    groups << current if current.present?
    raise ArgumentError, "Extraction contains no data for flashcards" if groups.empty?

    groups
  end

  def slices(text)
    return [ text ] if text.length <= MAX_SOURCE_CHARACTERS

    text.scan(/.{1,#{MAX_SOURCE_CHARACTERS}}(?:\s+|\z)/m).map(&:strip).reject(&:empty?)
  end

  def deduplicate(cards)
    cards.uniq { |card| card.front.downcase.gsub(/\s+/, " ") }
  end
end
