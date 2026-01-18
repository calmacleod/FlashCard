require "csv"

class FlashCardGenerationJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = FlashCardRequest.find(request_id)
    request.update!(status: "processing", progress: 1)
    request.append_log!("Job started")
    request.append_log!("Generation model: #{request.model}")
    request.append_log!("Embedding model: #{request.embedding_model}")

    request.set_step!("Vectorizing PDF", progress: 5)
    request.append_log!("Extracting text and generating embeddings…")

    last_logged_chunk = 0
    vector_result = PdfVectorizer.vectorize(request.pdf_path, embedding_model: request.embedding_model) do |index:, total:|
      progress = 5 + ((index.to_f / total) * 45).round
      request.update!(progress:) if (progress > request.progress)

      # Avoid spamming DB writes/logs: log every 10 chunks and the final chunk.
      if index == total || (index - last_logged_chunk) >= 10
        request.append_log!("Embedded chunk #{index}/#{total}")
        last_logged_chunk = index
      end
    end
    request.update!(
      vector_path: vector_result.vector_path,
      progress: 50,
      current_step: "Generating cards"
    )
    request.append_log!("Embeddings saved to #{vector_result.vector_path}")

    prompt = FlashCardPromptBuilder.build(
      pdf_text: vector_result.text,
      guidance: request.guidance.to_s,
      notes: request.notes.to_s
    )
    request.update!(prompt_text: prompt)

    request.update!(progress: 70)
    request.append_log!("Calling Ollama /api/generate…")
    response = OllamaClient.new.generate(prompt:, model: request.model)

    request.update!(progress: 85)
    request.append_log!("Parsing model response into cards…")
    cards = FlashCardCardsExtractor.extract(response.text)
    request.append_log!("Built #{cards.length} cards")

    request.update!(progress: 92)
    request.append_log!("Rendering CSV…")
    csv = CSV.generate(row_sep: "\n", force_quotes: true) do |out|
      cards.each { |front, back| out << [front, back] }
    end

    request.update!(
      response_text: csv,
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
end
