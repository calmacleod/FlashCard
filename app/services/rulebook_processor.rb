class RulebookProcessor
  Unit = Data.define(:rule_number, :section, :article, :text)
  ExtractionError = Class.new(StandardError)

  TOKENS_PER_WORD   = 0.75
  TARGET_MIN_TOKENS = 300
  TARGET_MAX_TOKENS = 600
  OVERLAP_TOKENS    =  75

  TARGET_MIN_WORDS = (TARGET_MIN_TOKENS / TOKENS_PER_WORD).ceil  # ~400
  TARGET_MAX_WORDS = (TARGET_MAX_TOKENS / TOKENS_PER_WORD).ceil  # ~800
  OVERLAP_WORDS    = (OVERLAP_TOKENS    / TOKENS_PER_WORD).ceil  # ~100

  class UnitSchema < RubyLLM::Schema
    array :units do
      object do
        string :rule_number
        string :section
        string :article
        string :text
      end
    end
  end

  def self.process(pdf_path, model: "gemini-2.5-flash", delay: 0)
    new(pdf_path, model:, delay:).run
  end

  def initialize(pdf_path, model:, delay: 0)
    @pdf_path = pdf_path
    @model    = model
    @delay    = delay.to_f
  end

  def run
    print "Extracting text from #{File.basename(@pdf_path)}... "
    text = extract_text
    puts "done"

    records = load_or_build_chunks(text)
    done    = records.count(&:completed?)
    puts "#{records.size} chunks (#{done} already done)\n\n"

    @start_time  = Time.now
    @total_units = records.sum { |r| r.completed? ? r.units.size : 0 }

    records.each_with_index { |record, i| process_chunk(record, i + 1, records.size) }

    elapsed = Time.now - @start_time
    puts "─" * 60
    puts "Finished: #{@total_units} units extracted from #{records.size} chunks in #{format_duration(elapsed)}"
  end

  private

  def load_or_build_chunks(text)
    key      = File.expand_path(@pdf_path)
    existing = RulebookChunk.for_pdf(key).to_a
    return existing if existing.any?

    raw = build_chunks(text)
    raw.each_with_index.map do |chunk_text, i|
      RulebookChunk.create!(
        pdf_path:    key,
        chunk_index: i,
        chunk_text:  chunk_text,
        status:      "pending"
      )
    end
  end

  def print_units(units)
    if units.empty?
      puts "  (no structured units found)"
    else
      units.each_with_index do |u, i|
        rule_number = u.is_a?(Hash) ? u["rule_number"] : u.rule_number
        section     = u.is_a?(Hash) ? u["section"]     : u.section
        article     = u.is_a?(Hash) ? u["article"]     : u.article
        text        = u.is_a?(Hash) ? u["text"]        : u.text
        label = [ rule_number, section, article ].compact.reject(&:empty?).join(" | ")
        puts "  [#{i + 1}] #{label.empty? ? '(no label)' : label}"
        puts "       #{text.to_s.strip[0, 160]}#{'...' if text.to_s.length > 160}"
      end
    end
  end

  def extract_text
    Pdftotext.text(@pdf_path)
  rescue => e
    raise ExtractionError, "pdftotext failed: #{e.message}"
  end

  def build_chunks(text)
    paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
    chunks     = []
    buffer     = []
    word_count = 0

    paragraphs.each do |para|
      pw = para.split.size
      if word_count + pw > TARGET_MAX_WORDS && word_count >= TARGET_MIN_WORDS
        chunks << buffer.join("\n\n")
        overlap_text = buffer.join(" ").split.last(OVERLAP_WORDS).join(" ")
        buffer     = overlap_text.empty? ? [] : [ overlap_text ]
        word_count = buffer.first&.split&.size || 0
      end
      buffer     << para
      word_count += pw
    end

    chunks << buffer.join("\n\n") unless buffer.empty?
    chunks
  end

  def process_chunk(record, index, total)
    if record.completed?
      pct = (index * 100.0 / total).round
      bar = progress_bar(index, total)
      units = record.units
      print "\r[#{bar}] #{pct}%  chunk #{index}/#{total}  #{units.size} units  (cached)  "
      $stdout.flush
      puts
      print_units(units)
      puts
      return
    end

    pct     = ((index - 1) * 100.0 / total).round
    elapsed = @start_time ? format_duration(Time.now - @start_time) : "0s"
    bar     = progress_bar(index - 1, total)
    print "\r[#{bar}] #{pct}%  chunk #{index}/#{total}  elapsed #{elapsed}  "
    $stdout.flush

    chunk_start = Time.now
    units       = extract_units(record.chunk_text)
    chunk_time  = Time.now - chunk_start
    @total_units += units.size

    record.update!(
      units_json: units.map { |u| { rule_number: u.rule_number, section: u.section, article: u.article, text: u.text } }.to_json,
      status: "completed"
    )

    pct = (index * 100.0 / total).round
    bar = progress_bar(index, total)
    print "\r[#{bar}] #{pct}%  chunk #{index}/#{total}  #{units.size} units  #{chunk_time.round(1)}s  "
    $stdout.flush
    puts

    print_units(units)
    puts

    sleep(@delay) if @delay > 0 && index < total
  rescue => e
    record.update!(status: "failed")
    raise
  end

  def extract_units(chunk_text)
    chat     = RubyLLM.chat(model: @model)
    response = chat
                 .with_thinking(budget: 0)
                 .with_schema(UnitSchema)
                 .ask(prompt_for(chunk_text))
    parse_response(response.content)
  rescue JSON::ParserError => e
    warn "  [WARN] JSON parse failed: #{e.message}"
    []
  end

  def parse_response(content)
    data       = content.is_a?(Hash) ? content : JSON.parse(content)
    units_data = data.fetch("units", [])
    units_data.filter_map do |u|
      text = u["text"].to_s.strip
      next if text.empty?
      Unit.new(
        rule_number: u["rule_number"]&.strip,
        section:     u["section"]&.strip,
        article:     u["article"]&.strip,
        text:        text
      )
    end
  end

  BAR_WIDTH = 30

  def progress_bar(done, total)
    filled = total.zero? ? 0 : (done * BAR_WIDTH / total)
    "█" * filled + "░" * (BAR_WIDTH - filled)
  end

  def format_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60
    m, s = seconds.divmod(60)
    "#{m.to_i}m#{s.to_i}s"
  end

  def prompt_for(chunk_text)
    <<~PROMPT
      You are extracting structured units from a sports/game rulebook.

      For the text below, identify every distinct Rule, Section, or Article.

      For each unit, extract:
      - rule_number: e.g. "Rule 5", "Rule 5.3" (omit if not present)
      - section: e.g. "Section 3 – Player Equipment" (omit if not present)
      - article: e.g. "Article 4" (omit if not present)
      - text: the complete text of that rule/section/article (required)

      If the text contains no identifiable rules or sections, return an empty units array.

      TEXT:
      #{chunk_text}
    PROMPT
  end
end
