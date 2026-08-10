class DocumentExtractionJob < ApplicationJob
  queue_as :default

  def perform(extraction_id)
    extraction = DocumentExtraction.find(extraction_id)
    extraction.update!(status: "processing", error: nil, progress: { "chunks_done" => 0 })
    broadcast(extraction.document)

    result = DocumentDataExtractor.extract(
      extraction.document,
      schema: extraction.schema_snapshot,
      model_key: extraction.model_key,
      thinking: extraction.thinking,
      on_progress: ->(done, total) {
        extraction.update_columns(progress: { "chunks_done" => done, "chunks_total" => total })
        broadcast(extraction.document)
      }
    )

    extraction.update!(status: "completed", result:, error: nil)
    broadcast(extraction.document)
  rescue => error
    extraction&.update!(status: "failed", error: error.message)
    broadcast(extraction.document) if extraction
    raise
  end

  private

  def broadcast(document)
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{document.id}_status")
  end
end
