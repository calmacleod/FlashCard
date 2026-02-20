require "csv"

# Reads normalized RulebookEntry rows from a source CSV, groups them by
# rule → section, asks the LLM to produce Anki-compatible flashcards for
# each section, and writes a two-column CSV (front, back).
#
# Usage:
#   RulebookFlashcardGenerator.generate("path/to/entries.csv")
#   RulebookFlashcardGenerator.generate("path/to/entries.csv", model: "gemini-2.5-flash", output: "cards.csv")
class RulebookFlashcardGenerator
  Card = Data.define(:reference, :front, :back)
  GenerationError = Class.new(StandardError)

  class CardSchema < RubyLLM::Schema
    array :cards do
      object do
        string :reference   # e.g. "Rule 5 | Section 3 – Equipment | Article 2"
        string :front       # the question
        string :back        # the answer
      end
    end
  end

  BAR_WIDTH = 30

  def self.generate(csv_path, model: "gemini-3-flash-preview", output: nil, delay: 0)
    new(csv_path, model:, output:, delay:).run
  end

  def initialize(csv_path, model:, output: nil, delay: 0)
    @csv_path = File.expand_path(csv_path)
    @model    = model
    @output   = output ? File.expand_path(output) : default_output_path
    @delay    = delay.to_f
  end

  def run
    entries = load_entries
    puts "Loaded #{entries.size} entries from #{File.basename(@csv_path)}"

    groups = group_by_rule_section(entries)
    puts "#{groups.size} rule/section groups to process\n\n"

    @all_cards     = []
    @start_time    = Time.now
    @input_tokens  = 0
    @output_tokens = 0
    total          = groups.size

    groups.each_with_index do |(key, group_entries), i|
      generate_for_group(key, group_entries, i + 1, total)
      sleep(@delay) if @delay > 0 && i + 1 < total
    end

    write_csv

    elapsed = Time.now - @start_time
    puts "─" * 60
    puts "Finished: #{@all_cards.size} cards from #{total} groups in #{format_duration(elapsed)}"
    puts "Output: #{@output}"
    print_token_summary
  end

  private

  def load_entries
    RulebookEntry.for_csv(@csv_path).to_a
  rescue => e
    raise GenerationError, "Failed to load entries: #{e.message}"
  end

  # Group by [rule_number, section]. Articles within the same section are
  # bundled together so the LLM sees the full section context.
  def group_by_rule_section(entries)
    groups = {}
    entries.each do |entry|
      key = [ entry.rule_number.to_s.strip.presence, entry.section.to_s.strip.presence ]
      groups[key] ||= []
      groups[key] << entry
    end
    groups
  end

  def generate_for_group(key, entries, index, total)
    rule_number, section = key
    label   = build_label(rule_number, section)
    pct     = ((index - 1) * 100.0 / total).round
    elapsed = format_duration(Time.now - @start_time)
    bar     = progress_bar(index - 1, total)

    print "\r[#{bar}] #{pct}%  group #{index}/#{total}  #{label}  elapsed #{elapsed}  "
    $stdout.flush

    chunk_start = Time.now
    cards       = generate_cards(rule_number, section, entries)
    @all_cards.concat(cards)

    chunk_time = Time.now - chunk_start
    pct = (index * 100.0 / total).round
    bar = progress_bar(index, total)
    print "\r[#{bar}] #{pct}%  group #{index}/#{total}  #{label}  #{cards.size} cards  #{chunk_time.round(1)}s  "
    $stdout.flush
    puts
  rescue => e
    warn "\n  [ERROR] group #{index} (#{label}): #{e.message}"
  end

  def generate_cards(rule_number, section, entries)
    chat     = RubyLLM.chat(model: @model)
    response = chat
                 .with_thinking(budget: 0)
                 .with_schema(CardSchema)
                 .ask(prompt_for(rule_number, section, entries))

    @input_tokens  += response.input_tokens.to_i
    @output_tokens += response.output_tokens.to_i
    data = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    (data["cards"] || []).filter_map do |c|
      front = c["front"].to_s.strip
      back  = c["back"].to_s.strip
      next if front.empty? || back.empty?
      Card.new(reference: c["reference"].to_s.strip, front:, back:)
    end
  rescue JSON::ParserError => e
    warn "\n  [WARN] JSON parse failed: #{e.message}"
    []
  end

  def write_csv
    CSV.open(@output, "w") do |csv|
      csv << %w[front back]
      @all_cards.each do |card|
        # Embed the rule/section/article reference in the front of the card
        front_with_ref = card.reference.empty? ? card.front : "#{card.front}\n\n<i>#{card.reference}</i>"
        csv << [ front_with_ref, card.back ]
      end
    end
  end

  def prompt_for(rule_number, section, entries)
    rule_label    = rule_number.presence    || "(no rule)"
    section_label = section.presence        || "(no section)"
    context_label = build_label(rule_number, section)

    articles_text = entries.map do |e|
      parts = []
      parts << "Article: #{e.article}" if e.article.to_s.strip.present?
      parts << e.text.to_s.strip
      parts.join("\n")
    end.join("\n\n---\n\n")

    <<~PROMPT
      You are creating Anki flashcards from a sports/game rulebook.

      Focus area: #{context_label}
      Rule: #{rule_label}
      Section: #{section_label}

      SOURCE TEXT (articles within this section):
      #{articles_text}

      INSTRUCTIONS:
      1. Create one flashcard per meaningful concept, rule requirement, or article.
      2. Each card must have:
         - "reference": a precise citation like "Rule 5 | Section 3 – Equipment | Article 2"
           (omit levels that are absent, but always include at least what is known)
         - "front": a clear, specific question that tests understanding — not just recall of a phrase.
           Good questions start with "What...", "When...", "How many...", "Under what condition...", etc.
         - "back": a concise, complete answer directly derived from the rule text.
      3. Prioritise questions about:
         - Specific requirements, limits, or measurements
         - When a rule applies or exceptions to a rule
         - Penalties or consequences for violations
         - Definitions of terms used in the rule
      4. Do NOT produce trivially obvious or duplicate questions.
      5. Do NOT invent information — only use what appears in the source text.
      6. Aim for 2–6 cards per article. Fewer is better if the text is sparse.

      Return a JSON object with a "cards" array.
    PROMPT
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

  def build_label(rule_number, section)
    [ rule_number.presence, section.presence ].compact.join(" | ").presence || "(ungrouped)"
  end

  def default_output_path
    stem = File.basename(@csv_path, File.extname(@csv_path))
    File.join(File.dirname(@csv_path), "#{stem}_anki.csv")
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
