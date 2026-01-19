class FlashCardRefinementJob < ApplicationJob
  queue_as :default

  def perform(request_id, instruction)
    request = FlashCardRequest.find(request_id)
    request.update!(status: "processing", current_step: "Refining cards", progress: 10, refinement_prompt: instruction)
    request.append_log!("Refinement started")

    cards = request.flash_cards.order(:chunk_index, :id).to_a
    total = cards.length
    if total.zero?
      request.append_log!("No cards found to refine")
      request.update!(status: "completed", current_step: "Completed", progress: 100)
      return
    end

    kept = 0
    changed = 0
    discarded = 0
    request.append_log!("Refining #{total} cards…")

    cards.each_with_index do |card, index|
      progress = 10 + (((index + 1).to_f / total) * 80).round
      request.update!(progress:)

      prompt = FlashCardRefinementPromptBuilder.build(
        card_front: card.front,
        card_back: card.back,
        user_instruction: instruction
      )
      response = OllamaClient.new.generate(prompt:, model: request.model)
      decision = FlashCardDecisionParser.parse(response.text)

      case decision[:action]
      when "keep"
        card.update!(status: "kept", refined_front: nil, refined_back: nil, refinement_reason: decision[:reason])
        kept += 1
      when "change"
        card.update!(
          status: "changed",
          refined_front: decision[:front].presence || card.front,
          refined_back: decision[:back].presence || card.back,
          refinement_reason: decision[:reason]
        )
        changed += 1
      when "discard"
        card.update!(status: "discarded", refined_front: nil, refined_back: nil, refinement_reason: decision[:reason])
        discarded += 1
      end

      request.append_log!(
        "Refined #{index + 1}/#{total}: #{decision[:action]} (kept=#{kept}, changed=#{changed}, discarded=#{discarded})"
      )
    end

    request.update!(status: "completed", current_step: "Completed", progress: 100)
    request.append_log!("Refinement summary: kept=#{kept}, changed=#{changed}, discarded=#{discarded}")
    request.append_log!("Refinement completed")
  rescue StandardError => error
    request&.append_log!("ERROR: #{error.class}: #{error.message}")
    request&.update!(status: "failed", progress: 100, current_step: "Failed", error_message: error.message)
    raise
  end
end
