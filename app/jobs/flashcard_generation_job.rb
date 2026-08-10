class FlashcardGenerationJob < ApplicationJob
  queue_as :default

  def perform(document_id, persona_key = nil)
    @document = Document.find(document_id)
    extraction = @document.latest_completed_extraction
    raise ArgumentError, "Extract document data before generating flashcards" unless extraction

    persona = FlashcardPersona.find!(persona_key.presence || @document.flashcard_persona)
    settings = @document.llm_setting(:flashcards)
    entry = LlmModelCatalog.find!(settings.fetch("model"), capability: :structured_output)
    thinking = LlmModelCatalog.thinking_params(
      entry, effort: settings["effort"], budget: settings["budget"]
    )

    update_progress(stage: "generating_flashcards", groups_done: 0, flashcards_done: 0)
    cards = DocumentFlashcardGenerator.generate(
      extraction,
      model_key: entry.key,
      persona_key: persona.key,
      thinking:,
      on_progress: ->(done, total, count) {
        update_progress(
          stage: "generating_flashcards", groups_done: done,
          groups_total: total, flashcards_done: count, persona: persona.key
        )
      }
    )
    raise ArgumentError, "The model did not generate any usable flashcards" if cards.empty?

    Flashcard.transaction do
      @document.flashcards.delete_all
      cards.each_with_index do |card, position|
        @document.flashcards.create!(
          front: card.front, back: card.back,
          reference: card.reference.presence, position:
        )
      end
      @document.update!(
        flashcard_persona: persona.key,
        processing_status: "completed",
        processing_error: nil
      )
    end
    broadcast_status
    broadcast_refresh
  rescue => error
    @document&.update!(processing_status: "failed", processing_error: error.message)
    broadcast_status if @document
    broadcast_refresh if @document
    raise
  end

  private

  def update_progress(attrs)
    current = @document.progress
    @document.update_columns(
      processing_status: "processing",
      processing_error: nil,
      processing_progress: current.merge(attrs.stringify_keys).to_json
    )
    broadcast_status
  end

  def broadcast_status
    Turbo::StreamsChannel.broadcast_replace_to(
      "document_#{@document.id}_status",
      target: "flashcard-status",
      partial: "documents/flashcard_status",
      locals: { document: @document }
    )
  end

  def broadcast_refresh
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{@document.id}_status")
  end
end
