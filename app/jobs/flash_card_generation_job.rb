class FlashCardGenerationJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = FlashCardRequest.find(request_id)
    request.update!(status: "processing", progress: 1)
    request.append_log!("Job started")
    request.append_log!("Generation model: #{request.model}")
    request.append_log!("Detail level: #{request.detail_level}")

    request.set_step!("Using approved chunks", progress: 5)
    chunks = request.flash_card_chunks.where(approved: true).order(:index).to_a
    if chunks.empty?
      request.append_log!("No approved chunks found. Please review chunks before generating.")
      request.update!(status: "awaiting_approval", current_step: "Awaiting chunk approval", progress: 100)
      return
    end
    request.append_log!("Using #{chunks.length} approved chunks")

    request.flash_cards.delete_all
    request.set_step!("Generating cards", progress: 25)

    chunks.each_with_index do |chunk, index|
      percent = 25 + (((index + 1).to_f / chunks.length) * 60).round
      request.update!(progress: percent)
      request.append_log!("Generating cards for chunk #{index + 1}/#{chunks.length}: #{chunk.title}")

      min_cards, max_cards = card_targets_for(request.detail_level)
      prompt = FlashCardPromptBuilder.build(
        pdf_text: chunk.content_text,
        guidance: request.guidance.to_s,
        notes: request.notes.to_s,
        section_title: chunk.title.to_s,
        min_cards:,
        max_cards:
      )

      response = OllamaClient.new.generate(prompt:, model: request.model)

      request.append_log!("Model response preview (head): #{snippet(response.text, 500)}")
      request.append_log!("Model response preview (tail): #{snippet(response.text, 500, from_end: true)}")

      cards = FlashCardCardsExtractor.extract(response.text)
      cards = cards.first(max_cards)
      request.append_log!("Built #{cards.length} cards in section #{index + 1}")

      cards.each do |front, back|
        FlashCard.create!(
          flash_card_request: request,
          chunk_index: chunk.index,
          front:,
          back:
        )
      end
    end

    request.update!(
      status: "completed",
      progress: 100,
      current_step: "Completed"
    )
    request.append_log!("Job completed")
  rescue StandardError => error
    request&.append_log!("ERROR: #{error.class}: #{error.message}")
    request&.update!(status: "failed", progress: 100, current_step: "Failed", error_message: error.message)
    raise
  end

  private

  def card_targets_for(detail_level)
    case detail_level.to_s
    when "low"
      [2, 5]
    when "high"
      [8, 20]
    else
      [4, 10]
    end
  end

  def snippet(text, length, from_end: false)
    clean = text.to_s.gsub(/\s+/, " ").strip
    return "" if clean.empty?
    return clean[-length, length].to_s if from_end

    clean[0, length].to_s
  end
end
