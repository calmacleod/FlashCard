require "json"
require "csv"

class FlashCardCardsExtractor
  ExtractionError = Class.new(StandardError)

  # Returns array of [front, back]
  def self.extract(text)
    text = text.to_s.strip
    raise ExtractionError, "Empty model response" if text.empty?

    result =
      from_json(text) || from_json(extract_json_array(text)) || from_json(extract_json_object(text)) ||
      from_qa_blocks(text) || from_tsv(text) || from_csv(text)

    return result unless result.nil?

    raise ExtractionError, "Unable to parse model response into cards"
  end

  def self.from_json(text)
    return nil if text.nil?

    text = strip_code_fences(text)
    data = JSON.parse(text)
    if data.is_a?(Hash)
      data = data["cards"] || data[:cards]
    end
    return unless data.is_a?(Array)

    cards = data.filter_map do |item|
      next unless item.is_a?(Hash)

      front = item["front"] || item[:front]
      back = item["back"] || item[:back]
      next if front.nil? || back.nil?

      [front.to_s.strip, back.to_s.strip]
    end

    cards
  rescue JSON::ParserError
    nil
  end

  def self.from_qa_blocks(text)
    lines = text.lines.map(&:strip).reject(&:empty?)
    cards = []
    current_front = nil

    lines.each do |line|
      if line.start_with?("Q:", "Question:")
        current_front = line.split(":", 2).last.to_s.strip
      elsif line.start_with?("A:", "Answer:") && current_front
        back = line.split(":", 2).last.to_s.strip
        cards << [current_front, back] if back.present?
        current_front = nil
      end
    end

    cards if cards.any?
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

  def self.strip_code_fences(text)
    stripped = text.strip
    return stripped unless stripped.start_with?("```")

    stripped
      .sub(/\A```[a-zA-Z]*\s*\n?/, "")
      .sub(/```\s*\z/, "")
      .strip
  end

  def self.extract_json_array(text)
    return nil unless text.include?("[") && text.include?("]")

    start_idx = text.index("[")
    end_idx = text.rindex("]")
    return nil unless start_idx && end_idx && end_idx > start_idx

    text[start_idx..end_idx]
  end

  def self.extract_json_object(text)
    return nil unless text.include?("{") && text.include?("}")

    start_idx = text.index("{")
    end_idx = text.rindex("}")
    return nil unless start_idx && end_idx && end_idx > start_idx

    text[start_idx..end_idx]
  end
end
