class RulebookProcessor
  Unit = Data.define(:rule_number, :section, :article, :text)
  ExtractionError = Class.new(StandardError)

  TOKENS_PER_WORD   = 0.75
  TARGET_MIN_TOKENS = 700
  TARGET_MAX_TOKENS = 1000
  MAX_TOKENS        = 1200

  TARGET_MIN_WORDS = (TARGET_MIN_TOKENS / TOKENS_PER_WORD).ceil  # ~400
  TARGET_MAX_WORDS = (TARGET_MAX_TOKENS / TOKENS_PER_WORD).ceil  # ~800
  MAX_WORDS        = (MAX_TOKENS        / TOKENS_PER_WORD).ceil  # ~1600

  class UnitSchema < RubyLLM::Schema
    array :units do
      object do
        string :rule_number, required: false
        string :section, required: false
        string :article, required: false
        string :text, required: false
      end
    end
  end

  def self.process(pdf_path, model: "gemini-3-flash-preview", delay: 0, max_tokens: nil)
    new(pdf_path, model:, delay:, max_tokens:).run
  end

  def self.preview_text(pdf_path, show_chunks: false)
    instance = new(pdf_path, model: "")
    raw      = instance.send(:extract_text)
    clean    = instance.send(:strip_boilerplate, raw)
    clean    = instance.send(:ensure_section_breaks, clean)

    if show_chunks
      chunks  = instance.send(:build_chunks, clean)
      content = chunks.each_with_index.map do |chunk, i|
        "<<<CHUNK #{i}>>>\n#{chunk}"
      end.join("\n\n")
    else
      content = clean
    end

    stem    = File.basename(pdf_path, File.extname(pdf_path))
    outpath = Rails.root.join("#{stem}_preview.txt")
    File.write(outpath, content)
    puts "Wrote cleaned text to #{outpath}"
  end

  def self.token_count(pdf_path)
    instance = new(pdf_path, model: "")
    raw      = instance.send(:extract_text)
    clean    = instance.send(:strip_boilerplate, raw)
    words    = clean.split.size
    tokens   = (words * TOKENS_PER_WORD).round
    puts "#{File.basename(pdf_path)}: #{words} words ≈ #{tokens} tokens"
    tokens
  end

  def self.clear(pdf_path)
    key     = File.expand_path(pdf_path)
    deleted = RulebookChunk.for_pdf(key).delete_all
    puts "Cleared #{deleted} chunk(s) for #{File.basename(pdf_path)}"
  end

  def initialize(pdf_path, model:, delay: 0, max_tokens: nil)
    @pdf_path   = pdf_path
    @model      = model
    @delay      = delay.to_f
    @max_words  = max_tokens ? (max_tokens / TOKENS_PER_WORD).ceil : nil
  end

  def run
    print "Extracting text from #{File.basename(@pdf_path)}... "
    text = extract_text
    puts "done"

    records = load_or_build_chunks(text)
    done    = records.count(&:completed?)
    puts "#{records.size} chunks (#{done} already done)\n\n"

    preview_chunks(records)
    case confirm_proceed?
    when :abort  then return
    when :clear
      RulebookChunk.for_pdf(File.expand_path(@pdf_path)).delete_all
      puts "Chunks cleared."
      return
    end

    @start_time    = Time.now
    @total_units   = records.sum { |r| r.completed? ? r.units.size : 0 }
    @input_tokens  = 0
    @output_tokens = 0

    records.each_with_index { |record, i| process_chunk(record, i + 1, records.size) }

    elapsed = Time.now - @start_time
    puts "─" * 60
    puts "Finished: #{@total_units} units extracted from #{records.size} chunks in #{format_duration(elapsed)}"
    print_token_summary
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

  def preview_chunks(records)
    puts "─" * 60
    puts "CHUNK PREVIEW"
    puts "─" * 60
    records.each_with_index do |record, i|
      text       = record.chunk_text
      word_count = text.split.size
      status     = record.completed? ? " [cached]" : ""
      puts "\n── Chunk #{i + 1}/#{records.size}  (#{word_count} words)#{status} ──"
      puts text
    end
    puts "\n" + "─" * 60
  end

  def confirm_proceed?
    loop do
      print "Proceed with LLM extraction? [y/n/c (clear chunks)]: "
      $stdout.flush
      answer = $stdin.gets&.strip&.downcase
      return :proceed if answer == "y"
      return :abort   if answer == "n"
      return :clear   if answer == "c"
      puts "Please enter 'y', 'n', or 'c'."
    end
  end

  # Rule headings always start a new chunk: "Rule 2 — Officials"
  # Requires an em/en-dash or hyphen after the number to avoid false positives.
  RULE_HEADER_RE = /\A\s*Rule\s+\d+\s*[–—-]/i

  # Matches the start of a Rule / Section / Article heading.
  # Section headings always start a new chunk: "Section 6: Possession"
  # Requires the colon to avoid false positives on mid-sentence section mentions.
  SECTION_HEADER_RE = /\A\s*Section\s+\d+\s*:/i

  # Article headings are used as a fallback split point when a chunk is already
  # long and no section break has appeared: "Article 4 – Ball in Play"
  ARTICLE_HEADER_RE = /\A\s*Article\s+\d+/i

  # Footer boilerplate: "Canadian Amateur Rule Book for Tackle Football"
  # Appears in two forms — page number on either side:
  #   "Canadian Amateur Rule Book for Tackle Football   42"
  #   "42   Canadian Amateur Rule Book for Tackle Football"
  RULEBOOK_TITLE = /Canadian\s+Amateur\s+Rule\s+Book\s+for\s+Tackle\s+Football/i
  BOILERPLATE_RE = /
    ^
    (?:
      #{RULEBOOK_TITLE} \s* \d* |   # title then optional page number
      \d+ \s+ #{RULEBOOK_TITLE}     # page number then title
    )
    \s*$
  /xi

  # Standalone page numbers: a line containing only digits (optionally preceded
  # or followed by whitespace). Anchored to the full line to avoid stripping
  # numbers embedded in content.
  PAGE_NUMBER_RE = /^\s*\d+\s*$/

  # Casebook cross-references, e.g. "(CB42)", "(CB 7)"
  CB_REFERENCE_RE = /\(CB\s*\d+\)/i



  # Running page headers that appear in two mirrored forms:
  #   "Chapter Title   <spaces>   Rule N Section N Article N"
  #   "Rule N Section N Article N   <spaces>   Chapter Title"
  # The distinguishing feature is 3+ spaces separating two halves where one half
  # contains a Rule/Section/Article reference.
  RULE_REF = /(?:Rule|Section|Article)\s+[\dA-Z][\w.]*/i
  RUNNING_HEADER_RE = /
    ^                          # start of line
    (?!\s*Section\s+\d+\s*:)  # not a real Section heading  e.g. "Section 8:"
    (?:
      .+? \s{3,} #{RULE_REF} (?:\s+#{RULE_REF})* |   # "Title   Rule N Section N"
      #{RULE_REF} (?:\s+#{RULE_REF})* \s{3,} .+?      # "Rule N Section N   Title"
    )
    \s*$                       # end of line
  /xi

  def extract_text
    raw = Pdftotext.text(@pdf_path)
    raw.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").unicode_normalize
  rescue => e
    raise ExtractionError, "pdftotext failed: #{e.message}"
  end

  def strip_boilerplate(text)
    text
      .gsub(/\f/, "\n")          # form feeds → newlines so ^ anchors work
      .gsub(BOILERPLATE_RE, "")
      .gsub(RUNNING_HEADER_RE, "")
      .gsub(PAGE_NUMBER_RE, "")
      .gsub(CB_REFERENCE_RE, "")
  end

  def debug_header_lines(text)
    text.each_line do |line|
      next unless line =~ /Rule\s+\d+\s+Section/i
      puts "--- suspect line (#{line.bytesize} bytes) ---"
      puts line.chars.map { |c| c =~ /\s/ && c != " " ? "[#{c.inspect}]" : c }.join
      puts line.bytes.each_slice(16).map { |s| s.map { |b| "%02x" % b }.join(" ") }.join("\n")
      puts "match: #{line.chomp.match?(RUNNING_HEADER_RE)}"
      puts
    end
  end

  def rule_header?(para)
    para.match?(RULE_HEADER_RE)
  end

  def section_header?(para)
    para.match?(SECTION_HEADER_RE)
  end

  def article_header?(para)
    para.match?(ARTICLE_HEADER_RE)
  end

  # Guarantee that every Section heading starts on its own paragraph by
  # inserting a double newline before any Section line that isn't already
  # preceded by one. This handles PDFs where a section header is separated
  # from the previous line by only a single newline (or heavy indentation).
  def ensure_section_breaks(text)
    text.gsub(/(?<!\n\n)([ \t]*Section\s+\d+\s*:)/i) { "\n\n#{$1}" }
  end

  def flush_buffer(chunks, buffer)
    return if buffer.empty?
    chunks << buffer.join("\n\n")
  end

  def build_chunks(text)
    clean      = strip_boilerplate(text)
    clean      = ensure_section_breaks(clean)
    paragraphs = clean.split(/\n+/).map(&:strip).reject(&:empty?)
    chunks     = []
    buffer     = []
    word_count = 0

    puts "MAX WORDS: #{@max_words}"
    puts "HELLO?"

    paragraphs.each do |para|
      pw = para.split.size

      flush = if rule_header?(para) && buffer.any?
                # Always split at a Rule boundary
                true
              elsif section_header?(para) && buffer.any?
                # Always split at a Section boundary
                true
              elsif article_header?(para) && word_count >= TARGET_MIN_WORDS && buffer.any?
                # Split at an Article boundary only when the chunk is already long enough
                true
              elsif @max_words && buffer.any? && word_count + pw > @max_words
                # Hard cap: flush before adding a paragraph that would exceed the token limit
                true
              else
                false
              end

      if flush
        flush_buffer(chunks, buffer)
        buffer     = []
        word_count = 0
      end

      buffer     << para
      word_count += pw
    end

    flush_buffer(chunks, buffer)
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
  rescue => _e
    record.update!(status: "failed")
    raise
  end

  def extract_units(chunk_text)
    chat     = RubyLLM.chat(model: @model)
    response = chat
                 .with_thinking(effort: "minimal")
                 .with_temperature(0.1)
                 .with_schema(UnitSchema)
                 .ask(prompt_for(chunk_text))
    @input_tokens  += response.input_tokens.to_i
    @output_tokens += response.output_tokens.to_i
    parse_response(response.content)
  rescue JSON::ParserError => e
    warn "  [WARN] JSON parse failed: #{e.message}"
    []
  end

  def parse_response(content)
    data       = content.is_a?(Hash) ? content : JSON.parse(content)
    units_data = data.fetch("units", [])
    units_data.filter_map do |u|
      text        = u["text"].to_s.strip
      rule_number = u["rule_number"]&.strip
      section     = u["section"]&.strip
      article     = u["article"]&.strip
      # Keep heading-only units (no body text) as long as they have a label
      next if text.empty? && [ rule_number, section, article ].all?(&:blank?)
      Unit.new(
        rule_number: rule_number,
        section:     section,
        article:     article,
        text:        text
      )
    end
  end

  def print_token_summary
    total = @input_tokens + @output_tokens
    puts "\nToken usage:"
    puts "  Input:  #{@input_tokens.to_s.rjust(10)}"
    puts "  Output: #{@output_tokens.to_s.rjust(10)}"
    puts "  Total:  #{total.to_s.rjust(10)}"

    model_info = RubyLLM.models.find(@model)
    if model_info&.input_price_per_million && model_info&.output_price_per_million
      input_cost  = @input_tokens  * model_info.input_price_per_million  / 1_000_000.0
      output_cost = @output_tokens * model_info.output_price_per_million / 1_000_000.0
      puts "  Cost:   $#{format('%.4f', input_cost + output_cost)}"
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
      You are extracting structured units from a Canadian football rulebook.

      The rulebook uses a strict three-level hierarchy with these exact formats:
        - Rule:    "Rule <Number> – <Name>"       e.g. "Rule 1 – The Field"
        - Section: "Section <Number>: <Name>"     e.g. "Section 5: Timing"
        - Article: "Article <Number> – <Name>"    e.g. "Article 3 – Simultaneous Possession"

      For each unit found in the text below, extract:
        - rule_number: the full rule label including its name, e.g. "Rule 1 – The Field"
                       (omit if not present in this chunk)
        - section:     the full section label including its name, e.g. "Section 5: Timing"
                       (omit if not present in this chunk)
        - article:     the full article label including its name, e.g. "Article 3 – Simultaneous Possession"
                       (omit if not present in this chunk)
        - text:        the complete body text of that unit, not including the heading line itself.
                       May be empty if the chunk contains only a heading with no body text.

      Important:
        - Always capture the full label (number AND name) for rule_number, section, and article.
        - A unit's text runs until the next heading of the same or higher level.
        - Only populate rule_number, section, or article from an actual heading line that appears
          verbatim in the TEXT below. Never infer them from cross-references inside body text such as
          "see Rule 1, Section 5, Article 6" — those are citations to other parts of the rulebook,
          not headings that define the current unit.
        - Do not use your training data or prior knowledge of this rulebook. Extract only what is
          explicitly written in the TEXT. If you cannot see a heading printed in the TEXT, omit that field.
        - If a field (rule_number, section, article) has no corresponding heading in this chunk,
          omit it entirely rather than guessing from context.
        - If the chunk contains no identifiable rules, sections, or articles, return an empty units array.

      TEXT:
      #{chunk_text}
    PROMPT
  end
end
