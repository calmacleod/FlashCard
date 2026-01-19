require "json"

class SemanticChunker
  OutlineUnit = Data.define(:path, :title, :start_line)
  Chunk = Data.define(:index, :path, :title, :text)

  class OutlineError < StandardError; end

  # AI-driven semantic chunking:
  # 1) Ask the model to return outline units with line-number starts (no regex, no anchors)
  # 2) Validate line numbers are in range and monotonic
  # 3) Slice deterministically from start_line -> next start_line
  def self.chunk(text:, model:, user_hint: nil, max_units: 60, attempts: 2)
    normalized = text.to_s
    raise OutlineError, "Empty document text" if normalized.strip.empty?

    last_error = nil
    last_response = nil
    hint = user_hint

    attempts.times do |attempt|
      lines = normalize_lines(normalized)
      numbered = to_numbered_lines(lines)
      page_ends_by_line = page_end_line_by_line(lines)
      prompt = outline_prompt(numbered_text: numbered, user_hint: hint, max_units:, line_count: lines.length)
      response = OllamaClient.new.chat(
        messages: [{ role: "user", content: prompt }],
        model:,
        temperature: 0,
        format: outline_schema(lines.length)
      )
      last_response = response.text
      units = parse_units(last_response)

      units = units.first(max_units)
      validated = validate_and_sort_units(units, lines.length, lines:)
      return build_chunks(validated, lines, page_ends_by_line:)
    rescue OutlineError => error
      last_error = error
      # If the model didn't follow the JSON contract, re-try with a stronger instruction.
      next_hint = hint.to_s.strip
      next_hint = "None." if next_hint.empty?
      hint = <<~HINT
        #{next_hint}

        IMPORTANT: Your previous response could not be parsed as JSON. Return ONLY valid JSON matching the required shape.
        Do not include any other text.
      HINT

      break if attempt >= attempts - 1
    end

    message = last_error ? last_error.message : "Unknown outline error"
    if last_response
      message = "#{message}. Response head: #{snippet(last_response)}. Response tail: #{snippet(last_response, from_end: true)}"
    end
    raise OutlineError, message
  end

  def self.outline_schema(line_count)
    {
      type: "object",
      properties: {
        schema: { type: "string", enum: ["semantic_outline_v1"] },
        units: {
          type: "array",
          minItems: 1,
          items: {
            type: "object",
            properties: {
              path: { type: "array", items: { type: "string" } },
              title: { type: "string" },
              start_line: { type: "integer", minimum: 1, maximum: line_count }
            },
            required: ["path", "title", "start_line"]
          }
        }
      },
      required: ["schema", "units"]
    }
  end

  def self.outline_prompt(numbered_text:, user_hint:, max_units:, line_count:)
    hint = user_hint.to_s.strip
    hint = "None." if hint.empty?

    <<~PROMPT
      You are identifying semantic sections in a structured document (e.g., a rulebook or textbook).
      Your job is ONLY to produce a structural outline with line-number boundaries. Do not summarize.

      Return ONLY valid JSON (no markdown), with this shape:
      {
        "schema": "semantic_outline_v1",
        "units": [
          { "path": ["Rule 1", "Section 1.1"], "title": "Title here", "start_line": 123 }
        ]
      }

      Constraints:
      - start_line MUST be an integer line number between 1 and #{line_count}.
      - Choose start_line values that represent the start of a semantic unit (Rule/Section/Article/Chapter/etc).
      - Produce up to #{max_units} units.
      - Prefer leaf-level units (the smallest useful study sections).
      - VERY IMPORTANT: The text includes explicit page markers like "<<<PAGE 12>>>". Chunks should almost never span pages.
        - Prefer choosing start_line values shortly AFTER a page marker line.
        - If you are unsure, pick boundaries so that each page starts a new unit (one unit per page).
        - Do not create a unit that would require spanning across a page marker unless the page is clearly continuing the same section.
      - If you cannot find clear structure, still return units by meaningful topical breaks.
      - Do NOT invent structure; only choose boundaries that are clearly indicated in the provided lines.

      USER_HINT_ABOUT_STRUCTURE:
      #{hint}

      DOCUMENT_LINES (each line is prefixed with its line number):
      #{numbered_text}
    PROMPT
  end

  def self.parse_units(text)
    json = extract_json(text)
    payload = JSON.parse(json)

    units =
      if payload.is_a?(Array)
        payload
      elsif payload.is_a?(Hash)
        payload.fetch("units")
      else
        raise OutlineError, "Outline JSON must be an object or array"
      end

    outline_units = units.map do |unit|
      OutlineUnit.new(
        path: Array(unit["path"]).map(&:to_s),
        title: unit["title"].to_s,
        start_line: Integer(unit.fetch("start_line"))
      )
    end
    raise OutlineError, "Model returned an empty outline" if outline_units.empty?
    outline_units
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError => error
    raise OutlineError, "Unable to parse outline JSON: #{error.message}"
  end

  def self.extract_json(text)
    stripped = text.to_s.strip
    stripped = stripped.sub(/\A```[a-zA-Z]*\s*\n?/, "").sub(/```\s*\z/, "").strip

    # Prefer object form, but accept arrays too.
    obj_start = stripped.index("{")
    obj_end = stripped.rindex("}")
    if obj_start && obj_end && obj_end > obj_start
      return stripped[obj_start..obj_end]
    end

    arr_start = stripped.index("[")
    arr_end = stripped.rindex("]")
    if arr_start && arr_end && arr_end > arr_start
      return stripped[arr_start..arr_end]
    end

    raise OutlineError, "No JSON object found in outline response"
  end

  def self.snippet(text, length = 420, from_end: false)
    clean = text.to_s.gsub(/\s+/, " ").strip
    return "" if clean.empty?
    return clean[-length, length].to_s if from_end
    clean[0, length]
  end

  def self.validate_and_sort_units(units, line_count, lines:)
    in_range = units.select { |u| u.start_line.is_a?(Integer) && u.start_line.between?(1, line_count) }
    raise OutlineError, "Too few usable section starts found (#{in_range.length})" if in_range.empty?

    normalized = in_range.map { |u| normalize_unit_start_line(u, lines) }
    normalized = normalized.select { |u| u.start_line.between?(1, line_count) }
    raise OutlineError, "Too few usable section starts found after normalization (#{normalized.length})" if normalized.empty?

    sorted = normalized.sort_by(&:start_line)
    deduped = sorted.uniq { |u| u.start_line }
    raise OutlineError, "Too few usable unique section starts found (#{deduped.length})" if deduped.empty?

    deduped
  end

  def self.build_chunks(units, lines, page_ends_by_line:)
    chunks = []
    units.each_with_index do |unit, index|
      next_unit = units[index + 1]
      start_line_idx = unit.start_line - 1
      end_line_idx =
        if next_unit
          next_unit.start_line - 1
        else
          lines.length
        end

      # Strongly prefer ending chunks at the end of the page containing start_line.
      # This makes "chunks rarely span pages" a deterministic behavior even if the model outline is imperfect.
      page_end_line = page_ends_by_line[unit.start_line] || lines.length
      end_line_idx = [ end_line_idx, page_end_line ].min

      next unless end_line_idx > start_line_idx

      slice_lines = lines[start_line_idx...end_line_idx]
      slice_lines = slice_lines.reject { |l| page_marker?(l) }
      slice = slice_lines.join("\n").strip
      next if slice.empty?

      chunks << Chunk.new(index: chunks.length, path: unit.path, title: unit.title, text: slice)
    end

    if chunks.empty?
      raise OutlineError, "No chunks could be constructed from outline"
    end

    chunks
  end

  def self.normalize_unit_start_line(unit, lines)
    # If the model picked a page marker line, shift to the first content line of that page.
    idx = unit.start_line - 1
    if idx.between?(0, lines.length - 1) && page_marker?(lines[idx])
      next_idx = idx + 1
      return unit if next_idx >= lines.length
      return OutlineUnit.new(path: unit.path, title: unit.title, start_line: next_idx + 1)
    end

    unit
  end

  def self.page_marker?(line)
    line.to_s.strip.match?(/\A<<<PAGE\s+\d+>>>\z/)
  end

  # Returns a Hash mapping 1-based line_number => 1-based line_number of the page end (exclusive end index in build_chunks).
  # Example: if page ends at line 120 (next marker at 121), we return 121 so slicing can use ...121.
  def self.page_end_line_by_line(lines)
    marker_indexes = lines.each_index.select { |idx| page_marker?(lines[idx]) }
    return {} if marker_indexes.empty?

    # Each "page" starts at marker idx, and ends right before next marker idx.
    ranges =
      marker_indexes.map.with_index do |marker_idx, i|
        next_marker_idx = marker_indexes[i + 1]
        page_start_idx = marker_idx
        page_end_exclusive_idx = next_marker_idx || lines.length
        [page_start_idx, page_end_exclusive_idx]
      end

    ends_by_line = {}
    ranges.each do |start_idx, end_exclusive_idx|
      end_line_number = end_exclusive_idx # because line numbers are 1-based, and end_exclusive_idx is already exclusive
      (start_idx...end_exclusive_idx).each do |idx|
        ends_by_line[idx + 1] = end_line_number
      end
    end
    ends_by_line
  end

  def self.normalize_lines(text)
    text
      .to_s
      .gsub("\u0000", "")
      .lines
      .map { |l| l.rstrip }
  end

  def self.to_numbered_lines(lines, max_lines: 3500)
    # Keep within typical local model context while still giving enough structure.
    sliced = lines.first(max_lines)
    sliced.map.with_index(1) { |line, idx| format("L%05d: %s", idx, line) }.join("\n")
  end
end
