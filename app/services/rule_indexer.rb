class RuleIndexer
  BATCH_SIZE = 50

  def self.index_csv(source_csv_path)
    entries = RulebookEntry.for_csv(source_csv_path)
    total = entries.count
    puts "Indexing #{total} entries from #{source_csv_path}..."

    entries.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
      batch.each do |entry|
        vector = embed(entry.text.to_s)
        entry.update_columns(embedding: vector.pack("f*"))
      end
      puts "  Indexed batch #{batch_idx + 1} (#{[ (batch_idx + 1) * BATCH_SIZE, total ].min}/#{total})"
    end

    puts "Done."
  end

  def self.embed(text)
    RubyLLM.embed(text, model: "gemini-embedding-001").vectors
  end
  private_class_method :embed
end
