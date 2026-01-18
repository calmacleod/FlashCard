require "json"
require "securerandom"
require "fileutils"

class PdfVectorizer
  Result = Data.define(:text, :vector_path, :chunk_count)

  def self.vectorize(pdf_path, embedding_model:, max_chars: 12_000, chunk_size: 900, &on_progress)
    text = PdfTextExtractor.extract(pdf_path, max_chars:)
    chunks = chunk_text(text, chunk_size:)

    total = chunks.length
    vectors = chunks.each_with_index.map do |chunk, index|
      on_progress&.call(index: index + 1, total:)
      embedding = OllamaClient.new.embed(text: chunk, model: embedding_model)
      { text: chunk, embedding: embedding.vector }
    end

    storage_dir = Rails.root.join("storage", "vectors")
    FileUtils.mkdir_p(storage_dir)
    file_name = "vectors-#{SecureRandom.hex(12)}.json"
    path = storage_dir.join(file_name)

    File.write(path, JSON.pretty_generate(vectors))

    Result.new(text:, vector_path: path.to_s, chunk_count: chunks.length)
  end

  def self.chunk_text(text, chunk_size:)
    words = text.split(/\s+/)
    chunks = []
    current = []
    current_length = 0

    words.each do |word|
      if current_length + word.length + 1 > chunk_size
        chunks << current.join(" ")
        current = [word]
        current_length = word.length
      else
        current << word
        current_length += word.length + 1
      end
    end

    chunks << current.join(" ") if current.any?
    chunks
  end
end
