class ExtractionMarkdownRenderer
  def self.render(result, schema:)
    new(result, schema:).render
  end

  def initialize(result, schema:)
    @result = result.to_h.deep_stringify_keys
    @schema = schema.to_h.deep_stringify_keys
  end

  def render
    lines = []
    render_object(@result, @schema, level: 2, lines:)
    lines.join("\n").strip
  end

  private

  def render_object(value, schema, level:, lines:)
    properties = schema.fetch("properties", {})
    keys = properties.keys | value.keys

    keys.each do |key|
      child_schema = properties.fetch(key, {})
      label = child_schema["title"].presence || key.humanize
      required = Array(schema["required"]).include?(key)
      render_field(
        label, value[key], child_schema,
        present: value.key?(key), required:, level:, lines:
      )
    end
  end

  def render_field(label, value, schema, present:, required:, level:, lines:)
    add_heading(lines, level, "#{label}#{required ? " (required)" : ""}")
    lines << "*#{escape(schema["description"])}*" if schema["description"].present?

    unless present
      lines << "**Not extracted.**"
      lines << ""
      return
    end

    if empty_value?(value)
      lines << "_No value extracted._"
    elsif value.is_a?(Hash)
      render_object(value.deep_stringify_keys, schema, level: level + 1, lines:)
    elsif value.is_a?(Array)
      render_array(value, schema.fetch("items", {}), label:, level:, lines:)
    else
      render_scalar(value, lines:)
    end
    lines << ""
  end

  def render_array(values, item_schema, label:, level:, lines:)
    if values.all? { |value| value.is_a?(Hash) }
      values.each_with_index do |value, index|
        value = value.deep_stringify_keys
        identity = record_identity(value)
        title = record_title(label, identity, value, index)
        add_heading(lines, level + 1, title)
        render_object(value, item_schema, level: level + 2, lines:)
      end
    else
      values.each { |value| lines << "- #{escape(serialized_scalar(value))}" }
    end
  end

  def render_scalar(value, lines:)
    if value.is_a?(String)
      value.lines(chomp: true).each do |line|
        lines << (line.present? ? "> #{escape(line)}" : ">")
      end
    else
      lines << "`#{escape(serialized_scalar(value))}`"
    end
  end

  def record_identity(value)
    candidates = value.filter_map do |key, child|
      next unless key.match?(/(?:name|title|label|number|code|id)\z/) && scalar?(child) && child.present?

      child.to_s.squish
    end
    candidates.first(2).join(" — ").truncate(100)
  end

  def record_title(label, identity, value, index)
    base = label.singularize
    return "#{base} #{index + 1}" if identity.blank?

    has_identifier = value.any? do |key, child|
      key.match?(/(?:number|code|id)\z/) && scalar?(child) && child.present?
    end
    has_identifier ? "#{base} #{identity}" : "#{base} #{index + 1} — #{identity}"
  end

  def add_heading(lines, level, text)
    if level <= 6
      lines << "#{"#" * level} #{escape(text)}"
    else
      lines << "**#{escape(text)}**"
    end
    lines << ""
  end

  def escape(value)
    value.to_s.gsub(/([\\`*_{}\[\]()#+.!|<>-])/, '\\\\\1')
  end

  def serialized_scalar(value)
    value.is_a?(Hash) || value.is_a?(Array) ? JSON.generate(value) : value.to_s
  end

  def scalar?(value)
    !value.is_a?(Hash) && !value.is_a?(Array)
  end

  def empty_value?(value)
    value.nil? || value == "" || value == [] || value == {}
  end
end
