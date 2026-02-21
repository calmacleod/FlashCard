class RuleIndexer
  BATCH_SIZE = 50

  def self.index_csv(source_csv_path)
    entries = RulebookEntry.for_csv(source_csv_path)
    total = entries.count
    puts "Indexing #{total} entries from #{source_csv_path}..."

    entries.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
      batch.each do |entry|
        vector = embed(indexable_text(entry))
        entry.update_columns(embedding: vector.pack("f*"))
      end
      puts "  Indexed batch #{batch_idx + 1} (#{[ (batch_idx + 1) * BATCH_SIZE, total ].min}/#{total})"
    end

    puts "Done."
  end

  OLLAMA = OllamaClient.new(base_url: ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434"))
  EMBEDDING_MODEL = ENV.fetch("OLLAMA_EMBEDDING_MODEL", "bge-m3")

  def self.indexable_text(entry)
    label = [ entry.rule_number, entry.section, entry.article ]
              .map(&:presence)
              .compact
              .join(" › ")
    label.present? ? "#{label}\n#{entry.text}" : entry.text.to_s
  end
  private_class_method :indexable_text

  def self.embed(text)
    OLLAMA.embed(text: text, model: EMBEDDING_MODEL).vector
  end
  private_class_method :embed
end
