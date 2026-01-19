require "json"

class FlashCardDecisionParser
  ParseError = Class.new(StandardError)

  def self.parse(text)
    text = text.to_s.strip
    raise ParseError, "Empty decision response" if text.empty?

    json = extract_json(text)
    data = JSON.parse(json)

    action = data["action"].to_s.strip
    front = data["front"].to_s.strip
    back = data["back"].to_s.strip
    reason = data["reason"].to_s.strip

    unless %w[keep change discard].include?(action)
      raise ParseError, "Invalid action: #{action}"
    end

    { action:, front:, back:, reason: }
  rescue JSON::ParserError => error
    raise ParseError, "Invalid JSON: #{error.message}"
  end

  def self.extract_json(text)
    stripped = text
      .sub(/\A```[a-zA-Z]*\s*\n?/, "")
      .sub(/```\s*\z/, "")
      .strip

    return stripped if stripped.start_with?("{") && stripped.end_with?("}")

    start_idx = stripped.index("{")
    end_idx = stripped.rindex("}")
    raise ParseError, "No JSON object found" unless start_idx && end_idx && end_idx > start_idx

    stripped[start_idx..end_idx]
  end
end
