require "csv"

class RulebookNormalizer
  ExtractionError = Class.new(StandardError)

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

  BAR_WIDTH    = 30
  CONTEXT_WORDS = 400

  def self.normalize(csv_path, model: "gemini-2.5-flash", delay: 0, pdf_path: nil, direct: false)
    new(csv_path, model:, delay:, pdf_path:, direct:).run
  end

  def initialize(csv_path, model:, delay: 0, pdf_path: nil, direct: false)
    @csv_path = File.expand_path(csv_path)
    @model    = model
    @delay    = delay.to_f
    @pdf_path = pdf_path ? File.expand_path(pdf_path) : nil
    @direct   = direct
  end

  def run
    rows = load_csv
    puts "Loaded #{rows.size} rows from #{File.basename(@csv_path)}"

    RulebookEntry.where(source_csv: @csv_path).delete_all

    @chunk_map   = load_chunk_map
    groups       = group_by_rule(rows)
    @entry_index = 0
    @start_time  = Time.now
    total        = groups.size

    if @direct
      puts "Direct mode — skipping LLM, carrying forward context\n\n"
      direct_import(rows)
    else
      puts "#{total} rule groups to normalize\n\n"

      groups.each_with_index do |(rule_number, group_rows), i|
        normalize_group(rule_number, group_rows, i + 1, total)
        sleep(@delay) if @delay > 0 && i + 1 < total
      end
    end

    elapsed = Time.now - @start_time
    puts "─" * 60
    puts "Finished: #{@entry_index} entries written in #{format_duration(elapsed)}"
  end

  private

  def load_csv
    CSV.read(@csv_path, headers: true).map(&:to_h)
  rescue Errno::ENOENT
    raise ExtractionError, "CSV not found: #{@csv_path}"
  end

  def group_by_rule(rows)
    groups = {}
    rows.each do |row|
      key = row["rule_number"].to_s.strip.presence
      groups[key] ||= []
      groups[key] << row
    end
    # Move nil/blank group first
    blank_key = groups.keys.find { |k| k.nil? || k.empty? }
    if blank_key
      blank = groups.delete(blank_key)
      groups = { blank_key => blank }.merge(groups)
    end
    groups
  end

  def direct_import(rows)
    current_rule    = nil
    current_section = nil
    current_article = nil
    article_counter = 0

    rows.each do |row|
      text    = row["text"].to_s.strip
      rule    = row["rule_number"].to_s.strip.presence
      section = row["section"].to_s.strip.presence
      article = row["article"].to_s.strip.presence

      # Update context before any skip so heading-only rows (empty text)
      # still advance current_rule/section/article for all following rows.
      if rule && rule != current_rule
        current_rule    = rule
        current_section = nil
        current_article = nil
        article_counter = 0
      end

      if section && section != current_section
        current_section = section
        current_article = nil
        article_counter = 0
      end

      if article
        current_article = article
      elsif current_rule && current_section && current_article.nil?
        article_counter += 1
        current_article  = "Article #{article_counter}"
      end

      # Skip entries that have a rule but no section or article context — these
      # are bare rule headings with no structural home yet.
      next if current_rule && current_section.nil? && current_article.nil?

      RulebookEntry.create!(
        source_csv:  @csv_path,
        entry_index: @entry_index,
        rule_number: current_rule,
        section:     current_section,
        article:     current_article,
        text:        text
      )
      @entry_index += 1
    end
  end

  def normalize_group(rule_number, rows, index, total)
    label   = rule_number.presence || "(no rule)"
    pct     = ((index - 1) * 100.0 / total).round
    elapsed = format_duration(Time.now - @start_time)
    bar     = progress_bar(index - 1, total)
    print "\r[#{bar}] #{pct}%  group #{index}/#{total}  #{label}  elapsed #{elapsed}  "
    $stdout.flush

    chunk_indices = rows.map { |r| r["chunk"].to_i }.uniq.sort
    prev_text     = @chunk_map[chunk_indices.first - 1]
    next_text     = @chunk_map[chunk_indices.last  + 1]

    chunk_start = Time.now
    units       = normalize_with_llm(rule_number, rows, prev_text, next_text)

    units.each do |u|
      text = u["text"].to_s.strip
      next if text.empty?
      RulebookEntry.create!(
        source_csv:  @csv_path,
        entry_index: @entry_index,
        rule_number: u["rule_number"]&.strip.presence,
        section:     u["section"]&.strip.presence,
        article:     u["article"]&.strip.presence,
        text:        text
      )
      @entry_index += 1
    end

    chunk_time = Time.now - chunk_start
    pct  = (index * 100.0 / total).round
    bar  = progress_bar(index, total)
    print "\r[#{bar}] #{pct}%  group #{index}/#{total}  #{label}  #{units.size} units  #{chunk_time.round(1)}s  "
    $stdout.flush
    puts
  rescue => e
    warn "\n  [ERROR] group #{index} (#{label}): #{e.message}"
  end

  def normalize_with_llm(rule_number, rows, prev_text = nil, next_text = nil)
    chat     = RubyLLM.chat(model: @model)
    response = chat
                 .with_thinking(budget: 0)
                 .with_schema(UnitSchema)
                 .ask(prompt_for(rule_number, rows, prev_text, next_text))
    data = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    data.fetch("units", [])
  rescue JSON::ParserError => e
    warn "\n  [WARN] JSON parse failed: #{e.message}"
    []
  end

  def prompt_for(rule_number, rows, prev_text = nil, next_text = nil)
    rule_label = rule_number.presence || "(ungrouped)"
    rows_text  = rows.map do |r|
      parts = []
      parts << "Section: #{r['section']}"   if r["section"].to_s.strip.present?
      parts << "Article: #{r['article']}"   if r["article"].to_s.strip.present?
      parts << "Text: #{r['text'].to_s.strip}"
      parts.join("\n")
    end.join("\n\n---\n\n")

    context_block = build_context_block(prev_text, next_text)

    <<~PROMPT
      You are normalizing structured entries from a sports/game rulebook for rule: #{rule_label}.

      The rows below were extracted from a PDF by a first-pass LLM and may have inconsistent
      headings, duplicated entries, or missing section/article labels.

      Your tasks:
      1. Standardise heading text: apply consistent casing and punctuation for section and article labels within this rule.
      2. Merge consecutive rows that belong to the same section/article into a single unit.
      3. Infer and fill missing section or article headings from context where possible.
      4. Validate the hierarchy and correct any mismatches (e.g. an article that belongs under a different section).
      5. Preserve all meaningful text — do not discard any content.

      Return the cleaned units in order. Each unit must have a non-empty "text" field.
      Set "rule_number", "section", and "article" only when they are known; omit (leave empty) otherwise.

      ROWS:
      #{rows_text}
      #{context_block}
    PROMPT
  end

  def build_context_block(prev_text, next_text)
    return "" if prev_text.nil? && next_text.nil?

    prev_excerpt = prev_text ? excerpt(prev_text, :tail) : "(none)"
    next_excerpt = next_text ? excerpt(next_text, :head) : "(none)"

    <<~CONTEXT

      SURROUNDING CONTEXT (read-only — do not include this in your output):

      [PRECEDING CHUNK — final ~#{CONTEXT_WORDS} words]
      #{prev_excerpt}

      [FOLLOWING CHUNK — first ~#{CONTEXT_WORDS} words]
      #{next_excerpt}

      Use this context only to inform heading inference, hierarchy validation, and
      boundary decisions. Do not reproduce it in your output units.
    CONTEXT
  end

  def excerpt(text, position)
    words = text.to_s.split
    case position
    when :tail then words.last(CONTEXT_WORDS).join(" ")
    when :head then words.first(CONTEXT_WORDS).join(" ")
    end
  end

  def load_chunk_map
    return {} unless @pdf_path
    RulebookChunk.for_pdf(@pdf_path).pluck(:chunk_index, :chunk_text).to_h
  end

  def progress_bar(done, total)
    filled = total.zero? ? 0 : (done * BAR_WIDTH / total)
    "█" * filled + "░" * (BAR_WIDTH - filled)
  end

  def format_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60
    m, s = seconds.divmod(60)
    "#{m.to_i}m#{s.to_i}s"
  end
end
