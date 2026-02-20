class RulebookReviewer
  def self.review(pdf_path, chunk: nil, full_text: false)
    new(pdf_path, chunk:, full_text:).run
  end

  def initialize(pdf_path, chunk: nil, full_text: false)
    @key          = File.expand_path(pdf_path)
    @chunk_filter = chunk
    @full_text    = full_text
  end

  def run
    records = RulebookChunk.for_pdf(@key).to_a

    if records.empty?
      puts "No chunks found for #{@key}"
      puts "Run RulebookProcessor.process(path) first."
      return
    end

    records = records.select { |r| r.chunk_index == @chunk_filter } if @chunk_filter

    print_summary(records)
    puts

    records.each { |r| print_chunk(r) }
  end

  private

  def print_summary(records)
    total     = records.size
    completed = records.count(&:completed?)
    failed    = records.count { |r| r.status == "failed" }
    pending   = records.count { |r| r.status == "pending" }
    total_units = records.sum { |r| r.units.size }

    puts "═" * 70
    puts "PDF:      #{@key}"
    puts "Chunks:   #{total}  (#{completed} completed, #{pending} pending, #{failed} failed)"
    puts "Units:    #{total_units} extracted"
    puts "═" * 70
  end

  def print_chunk(record)
    status_tag = case record.status
    when "completed" then "✓"
    when "failed"    then "✗"
    else                  "…"
    end

    puts "┌─ Chunk #{record.chunk_index}  [#{status_tag}]  #{record.units.size} units"
    puts "│  Source text (#{record.chunk_text.split.size} words):"
    if @full_text
      record.chunk_text.lines.each { |l| puts "│    #{l.rstrip}" }
    else
      record.chunk_text.lines.first(3).each { |l| puts "│    #{l.rstrip}" }
      puts "│    ..." if record.chunk_text.lines.size > 3
    end
    puts "│"

    units = record.units
    if units.empty?
      puts "│  (no units extracted)"
    else
      units.each_with_index do |u, i|
        label = [ u["rule_number"], u["section"], u["article"] ]
                  .compact.reject(&:empty?).join(" | ")
        puts "│  [#{i + 1}] #{label.empty? ? '(no label)' : label}"
        text = u["text"].to_s.strip
        text.scan(/.{1,80}/).first(4).each { |line| puts "│       #{line}" }
        puts "│       ..." if text.length > 320
      end
    end

    puts "└" + "─" * 69
    puts
  end
end
