
class Pipeline
  def initialize(
    chunk_size: 512,
    overlap: 0,
    categorizer_model: ChunkCategorizer::DEFAULT_MODEL,
    answerer_model: ChunkAnswerer::DEFAULT_MODEL
  )
    @chunk_size  = chunk_size
    @chunker     = TextChunker.new(chunk_size: chunk_size, overlap: overlap)
    @categorizer = ChunkCategorizer.new(model: categorizer_model)
    @answerer    = ChunkAnswerer.new(model: answerer_model)
  end

  # Returns:
  #   :categorized — Array<ChunkCategorizer::Result>
  #                  each result carries: category (dotted string), chunk (EnrichedChunk)
  #                  — access .chunk.first_page / .chunk.byte_start etc. to link back to the PDF
  def run(pdf_path)
    extraction  = PdfToText.extract(pdf_path, chunk_size: @chunk_size)
    chunks      = @chunker.chunk(extraction)
    categorized = @categorizer.categorize(chunks)

    { categorized: categorized }
  end

  # Answer a question against previously categorized chunks.
  #
  #   result   = pipeline.run("rules.pdf")
  #   response = pipeline.answer("What is a major foul?", result[:categorized])
  #   response.answer   # => "A major foul is... [2][5]"
  #   response.chunks   # => [EnrichedChunk(page=3,...), EnrichedChunk(page=7,...)]
  def answer(prompt, categorized_chunks)
    @answerer.answer(prompt, categorized_chunks)
  end
end
