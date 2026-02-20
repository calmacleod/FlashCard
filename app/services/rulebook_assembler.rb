class RulebookAssembler
  ResolvedUnit = Data.define(:rule_number, :section, :article, :text, :chunk_index)

  LINE_WIDTH = 100

  def self.assemble(pdf_path, format: :console, show_chunks: false, chunk_from: nil, chunk_to: nil)
    new(pdf_path, format:, show_chunks:, chunk_from:, chunk_to:).run
  end

  def initialize(pdf_path, format: :console, show_chunks: false, chunk_from: nil, chunk_to: nil)
    @key         = File.expand_path(pdf_path)
    @format      = format
    @show_chunks = show_chunks
    @chunk_from  = chunk_from
    @chunk_to    = chunk_to
  end

  def run
    records = RulebookChunk.for_pdf(@key).completed.to_a
    records = records.select { |r| r.chunk_index >= @chunk_from } if @chunk_from
    records = records.select { |r| r.chunk_index <= @chunk_to }   if @chunk_to

    if records.empty?
      puts "No completed chunks found for #{@key}"
      puts "Run RulebookProcessor.process(path) first."
      return
    end

    units = resolve_units(records)

    case @format
    when :markdown then write_markdown(units, records.size)
    when :csv      then write_csv(units, records.size)
    else                print_console(units, records.size)
    end
  end

  private

  # Walk every unit in chunk order and carry forward rule/section/article context.
  # A higher-level element appearing resets the lower-level context so we don't
  # bleed e.g. Section 3 of Rule 5 into Rule 6.
  def resolve_units(records)
    resolved        = []
    current_rule    = nil
    current_section = nil
    current_article = nil

    records.each do |record|
      record.units.each do |u|
        text        = u["text"].to_s.strip
        rule_number = u["rule_number"].to_s.strip.presence
        section     = u["section"].to_s.strip.presence
        article     = u["article"].to_s.strip.presence

        # Update context before any skip so heading-only units (empty text)
        # still advance current_rule/section/article for all following units.
        if rule_number && rule_number != current_rule
          current_rule    = rule_number
          current_section = nil
          current_article = nil
        end

        if section && section != current_section
          current_section = section
          current_article = nil
        end

        current_article = article if article

        next if text.empty?

        article_out, text_out = extract_leading_article_heading(current_article, text)
        current_article = article_out if article_out != current_article

        resolved << ResolvedUnit.new(
          rule_number: current_rule,
          section:     current_section,
          article:     current_article,
          text:        text_out,
          chunk_index: record.chunk_index
        )
      end
    end

    resolved
  end

  # ── Console output ───────────────────────────────────────────────────────

  def print_console(units, chunk_count)
    puts "═" * LINE_WIDTH
    puts "RULEBOOK: #{File.basename(@key)}"
    puts "#{chunk_count} chunks processed  ·  #{units.size} units assembled#{chunk_range_label}"
    puts "═" * LINE_WIDTH

    last_rule    = :none
    last_section = :none
    last_article = :none
    last_chunk   = :none

    units.each do |u|
      if @show_chunks && u.chunk_index != last_chunk && last_chunk != :none
        puts "  ┄" * (LINE_WIDTH / 3) + ""
        puts "  ┄ chunk #{last_chunk} → #{u.chunk_index}"
        puts "  ┄" * (LINE_WIDTH / 3) + ""
        puts
        last_chunk = u.chunk_index
      elsif last_chunk == :none
        last_chunk = u.chunk_index
      end

      if u.rule_number != last_rule
        puts unless last_rule == :none
        puts (u.rule_number || "(No Rule)").upcase
        puts "─" * LINE_WIDTH
        last_rule    = u.rule_number
        last_section = :none
        last_article = :none
      end

      if u.section != last_section
        puts if last_section != :none
        puts "  #{u.section}" if u.section
        last_section = u.section
        last_article = :none
      end

      if u.article != last_article
        puts "    #{u.article}" if u.article
        last_article = u.article
      end

      indent = case
               when u.article then "        "
               when u.section then "      "
               else                "    "
               end

      wrap(u.text, LINE_WIDTH - indent.length).each { |line| puts "#{indent}#{line}" }
      puts

      last_chunk = u.chunk_index
    end
  end

  # ── Markdown output ──────────────────────────────────────────────────────

  def write_markdown(units, chunk_count)
    stem    = File.basename(@key, File.extname(@key))
    outpath = Rails.root.join("#{stem}.md")
    lines   = build_markdown(units, chunk_count)

    File.write(outpath, lines.join("\n"))
    puts "Wrote #{units.size} units to #{outpath}"
  end

  def build_markdown(units, chunk_count)
    lines = []
    lines << "# #{File.basename(@key)}"
    lines << ""
    lines << "_#{chunk_count} chunks processed · #{units.size} units assembled#{chunk_range_label}_"
    lines << ""
    lines << "---"
    lines << ""

    last_rule    = :none
    last_section = :none
    last_article = :none
    last_chunk   = :none

    units.each do |u|
      if @show_chunks && u.chunk_index != last_chunk && last_chunk != :none
        lines << "> `chunk #{last_chunk} → #{u.chunk_index}`"
        lines << ""
        last_chunk = u.chunk_index
      elsif last_chunk == :none
        last_chunk = u.chunk_index
      end

      if u.rule_number != last_rule
        lines << "---" unless last_rule == :none
        lines << ""
        lines << "## #{u.rule_number || 'Uncategorised'}"
        lines << ""
        last_rule    = u.rule_number
        last_section = :none
        last_article = :none
      end

      if u.section != last_section
        lines << "### #{u.section}" if u.section
        lines << ""
        last_section = u.section
        last_article = :none
      end

      if u.article != last_article
        lines << "#### #{u.article}" if u.article
        lines << ""
        last_article = u.article
      end

      lines << u.text
      lines << ""

      last_chunk = u.chunk_index
    end

    lines
  end

  # ── CSV output ───────────────────────────────────────────────────────────

  def write_csv(units, chunk_count)
    require "csv"

    stem    = File.basename(@key, File.extname(@key))
    outpath = Rails.root.join("#{stem}.csv")

    CSV.open(outpath, "w") do |csv|
      csv << %w[chunk rule_number section article text]
      units.each do |u|
        csv << [ u.chunk_index, u.rule_number, u.section, u.article, u.text ]
      end
    end

    puts "Wrote #{units.size} units to #{outpath}"
  end

  # If the text begins with an article-like heading (e.g. "Article 1 – Length of Game"),
  # promote it to the article field (replacing a bare "Article 1" if present) and
  # strip it from the text so it isn't duplicated.
  #
  # Matches patterns like:
  #   "Article 1 – Length of Game\nThe game shall..."
  #   "Article 1\nThe game shall..."          ← bare duplicate, still strip
  ARTICLE_HEADING_RE = /\AArticle\s+[\d\.]+(?:\s*[–\-—]\s*[^\n]+)?\n+/i

  def extract_leading_article_heading(current_article, text)
    m = text.match(ARTICLE_HEADING_RE)
    return [ current_article, text ] unless m

    heading = m[0].strip
    rest    = text[m.end(0)..].strip

    # Prefer the longer/more descriptive of the two article labels
    promoted = (current_article.to_s.length >= heading.length) ? current_article : heading

    [ promoted, rest ]
  end

  def chunk_range_label
    return ""       unless @chunk_from || @chunk_to
    from = @chunk_from || 0
    to   = @chunk_to   || "end"
    "  ·  chunks #{from}–#{to}"
  end

  def wrap(text, width)
    text.gsub(/\s+/, " ").strip.scan(/\S.{0,#{width - 1}}(?=\s|$)/).map(&:strip)
  end
end
