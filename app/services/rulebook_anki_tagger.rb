require "csv"

# Reads a flashcard CSV produced by RulebookFlashcardGenerator and adds
# two new columns — "rule" and "section" — suitable for use as Anki tags.
#
# The rule/section values are extracted from the reference citation that
# RulebookFlashcardGenerator embeds in the front column, e.g.:
#   "What is X?\n\n<i>Rule 5 | Section 3 – Equipment | Article 2</i>"
#
# Usage:
#   RulebookAnkiTagger.tag("path/to/cards.csv")
#   RulebookAnkiTagger.tag("path/to/cards.csv", output: "path/to/tagged.csv")
class RulebookAnkiTagger
  TaggingError = Class.new(StandardError)

  def self.tag(csv_path, output: nil)
    new(csv_path, output:).run
  end

  def initialize(csv_path, output: nil)
    @csv_path = File.expand_path(csv_path)
    @output   = output ? File.expand_path(output) : default_output_path
  end

  def run
    rows = load_rows
    puts "Loaded #{rows.size} cards from #{File.basename(@csv_path)}"

    tagged = rows.map { |row| tag_row(row) }
    write_csv(tagged)

    puts "Tagged CSV written to #{@output}"
    @output
  end

  private

  def load_rows
    CSV.read(@csv_path, headers: true).map(&:to_h)
  rescue => e
    raise TaggingError, "Failed to load CSV: #{e.message}"
  end

  # Parse the <i>reference</i> embedded at the end of the front text.
  # Reference format: "Rule N | Section X – Title | Article Y"
  # Returns [rule_tag, section_tag] as underscore-slugged strings.
  def extract_tags(front)
    match = front.to_s.match(/<i>(.*?)<\/i>\s*\z/m)
    return [ "", "" ] unless match

    parts = match[1].split("|").map(&:strip)

    rule_tag    = slug(parts.find { |p| p.match?(/\Arule\s/i) })
    section_tag = slug(parts.find { |p| p.match?(/\Asection\s/i) })

    [ rule_tag, section_tag ]
  end

  def tag_row(row)
    rule_tag, section_tag = extract_tags(row["front"])
    tags = [ rule_tag, section_tag ].reject(&:empty?).join(" ")
    { "front" => row["front"], "back" => row["back"], "tags" => tags }
  end

  def write_csv(rows)
    CSV.open(@output, "w") do |csv|
      csv << %w[front back tags]
      rows.each { |row| csv << [ row["front"], row["back"], row["tags"] ] }
    end
  end

  def slug(str)
    return "" if str.nil? || str.strip.empty?
    str.strip.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
  end

  def default_output_path
    stem = File.basename(@csv_path, File.extname(@csv_path))
    File.join(File.dirname(@csv_path), "#{stem}_tagged.csv")
  end
end
