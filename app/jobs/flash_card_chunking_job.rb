class FlashCardChunkingJob < ApplicationJob
  queue_as :default

  def perform(request_id, user_hint: nil)
    request = FlashCardRequest.find(request_id)
    request.update!(status: "chunking", current_step: "Chunking document", progress: 5, chunking_status: "running", chunking_prompt: user_hint)
    request.append_log!("Chunking started")

    text = PdfTextExtractor.extract(request.pdf_path, max_chars: 120_000)
    request.update!(progress: 15)

    chunks =
      SemanticChunker.chunk(text:, model: request.model, user_hint:)

    request.flash_card_chunks.delete_all

    chunks.each do |chunk|
      FlashCardChunk.create!(
        flash_card_request: request,
        index: chunk.index,
        path_json: JSON.dump(chunk.path),
        title: chunk.title.presence || chunk.path.last.to_s.presence || "Section #{chunk.index + 1}",
        content_text: chunk.text,
        approved: false
      )
    end

    request.update!(
      status: "awaiting_approval",
      current_step: "Awaiting chunk approval",
      progress: 100,
      chunking_status: "complete"
    )
    request.append_log!("Chunking completed: #{chunks.length} chunks ready for review")
  rescue SemanticChunker::OutlineError => error
    request&.append_log!("Chunking failed: #{error.message}")
    request&.update!(status: "awaiting_approval", current_step: "Chunking needs review", chunking_status: "failed", error_message: error.message)
  rescue StandardError => error
    request&.append_log!("ERROR: #{error.class}: #{error.message}")
    request&.update!(status: "failed", progress: 100, current_step: "Failed", error_message: error.message, chunking_status: "failed")
    raise
  end
end
