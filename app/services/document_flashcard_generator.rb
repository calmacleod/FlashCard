class DocumentFlashcardGenerator
  Card = Data.define(:reference, :front, :back)
  MAX_SOURCE_CHARACTERS = 18_000

  def self.generate(extraction, model_key:, persona_key:, thinking: {}, on_progress: nil)
    new(
      extraction, model_key:, persona_key:, thinking:, on_progress:
    ).generate
  end

  def initialize(extraction, model_key:, persona_key:, thinking: {}, on_progress: nil)
    @extraction = extraction
    @entry = LlmModelCatalog.find!(model_key, capability: LlmModelCatalog::DOCUMENT_WORKFLOW_CAPABILITIES)
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
    source_label = "extracted source group #{index + 1} of #{total}"
    agent = DocumentFlashcardAgent.build(
      entry: @entry,
      thinking: @thinking,
      persona_name: @persona.name,
      persona_instructions: @persona.instructions,
      source_label:,
      source_tool: ReadWorkflowSourceTool.new(content: source, label: source_label.humanize)
    )
    response = agent.ask("Read #{source_label}, then create the best supported flashcards.")
    payload = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)

    Array(payload["cards"] || payload[:cards]).filter_map do |raw_card|
      raw_card = raw_card.stringify_keys
      front = raw_card["front"].to_s.strip
      back = raw_card["back"].to_s.strip
      next if front.blank? || back.blank?

      Card.new(reference: raw_card["reference"].to_s.strip, front:, back:)
    end
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
