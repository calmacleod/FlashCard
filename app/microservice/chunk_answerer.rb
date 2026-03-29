
class ChunkAnswerer
  DEFAULT_MODEL = "gpt-5.4-nano"

  SYSTEM_INSTRUCTIONS = <<~INSTRUCTIONS.strip
    You are an expert assistant that answers questions strictly from the provided document excerpts.

    Rules:
    - Answer only from the context chunks given. Do not invent facts not present in the chunks.
    - When you use information from a chunk, cite it inline as [N] where N is the chunk index.
    - If the answer spans multiple chunks, cite each relevant one.
    - If the context does not contain enough information to answer, say so explicitly.
    - Keep the answer concise and direct.
  INSTRUCTIONS

  # answer  — String, the LLM's answer with inline [N] citations
  # chunks  — Array<TextChunker::EnrichedChunk>, the cited source chunks
  #           (carry first_page, last_page, byte_start, byte_end for PDF linkback)
  Result = Data.define(:answer, :chunks)

  class AnswerSchema < RubyLLM::Schema
    string :answer,
      description: "Answer to the question with inline [N] citations for each referenced chunk"

    array :cited_chunk_indices, of: :integer,
      description: "Zero-based indices of the chunks cited in the answer"
  end

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  # prompt:  String                           — the user's question
  # chunks:  Array<ChunkCategorizer::Result>  — categorized chunks from the pipeline
  # returns: Result
  def answer(prompt, chunks)
    return Result.new(answer: "No context provided.", chunks: []) if chunks.empty?

    user_prompt = build_user_prompt(prompt, chunks)

    response = RubyLLM.chat(model: @model)
                      .with_instructions(SYSTEM_INSTRUCTIONS)
                      .with_thinking(budget: 0)
                      .with_schema(AnswerSchema)
                      .ask(user_prompt)

    raw         = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    answer_text = raw.fetch("answer", "").to_s.strip

    cited_indices = Array(raw.fetch("cited_chunk_indices", []))
      .map { |i| Integer(i) rescue nil }
      .compact
      .uniq
      .select { |i| i >= 0 && i < chunks.length }

    cited_chunks = cited_indices.map { |i| chunks[i].chunk }

    Result.new(answer: answer_text, chunks: cited_chunks)
  rescue => e
    Rails.logger.warn("ChunkAnswerer: failed (#{e.message})")
    Result.new(answer: "Failed to generate answer.", chunks: [])
  end

  private

  def build_user_prompt(prompt, chunks)
    lines = ["Context chunks:"]

    chunks.each_with_index do |result, idx|
      page_note = result.chunk.first_page ? " (page #{result.chunk.first_page})" : ""
      lines << ""
      lines << "--- CHUNK #{idx} [#{result.category}]#{page_note} ---"
      lines << result.chunk.content
      lines << "--- END CHUNK #{idx} ---"
    end

    lines << ""
    lines << "Question: #{prompt}"
    lines.join("\n")
  end
end
