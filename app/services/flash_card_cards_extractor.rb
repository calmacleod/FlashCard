require "json"
require "csv"

class FlashCardCardsExtractor
  ExtractionError = Class.new(StandardError)

  # Returns array of [front, back]
  def self.extract(text)
    text = text.to_s.strip
    raise ExtractionError, "Empty model response" if text.empty?

    from_json(text) || from_tsv(text) || from_csv(text) || raise(ExtractionError, "Unable to parse model response into cards")
  end

  def self.from_json(text)
    data = JSON.parse(text)
    return unless data.is_a?(Array)

    cards = data.filter_map do |item|
      next unless item.is_a?(Hash)

      front = item["front"] || item[:front]
      back = item["back"] || item[:back]
      next if front.nil? || back.nil?

      [front.to_s.strip, back.to_s.strip]
    end

    cards if cards.any?
  rescue JSON::ParserError
    nil
  end

  def self.from_tsv(text)
    rows = text.lines.map(&:strip).reject(&:empty?)
    cards = rows.filter_map do |line|
      front, back = line.split("\t", 2)
      next if front.nil? || back.nil?

      [front.to_s.strip, back.to_s.strip]
    end

    cards if cards.any?
  end

  def self.from_csv(text)
    cards = []
    CSV.parse(text, headers: false) do |row|
      next if row.nil? || row.empty?
      front = row[0]
      back = row[1]
      next if front.nil? || back.nil?

      cards << [front.to_s.strip, back.to_s.strip]
    end
    cards if cards.any?
  rescue CSV::MalformedCSVError
    nil
  end
end
