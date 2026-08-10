require "json"

class ExtractionResultMerger
  def self.merge(results, schema:)
    new(schema).merge(results)
  end

  def initialize(schema)
    @schema = schema
  end

  def merge(results)
    results.compact.reduce(nil) { |combined, result| merge_value(combined, result, @schema) } || {}
  end

  private

  def merge_value(left, right, schema)
    return compact_value(right, schema) if blank_value?(left)
    return compact_value(left, schema) if blank_value?(right)

    case schema_type(schema, left, right)
    when "object"
      merge_objects(left, right, schema)
    when "array"
      merge_arrays(left, right, schema)
    else
      left
    end
  end

  def merge_objects(left, right, schema)
    left = left.to_h.stringify_keys
    right = right.to_h.stringify_keys
    properties = schema.fetch("properties", {})

    (left.keys | right.keys).to_h do |key|
      [ key, merge_value(left[key], right[key], properties.fetch(key, {})) ]
    end.compact
  end

  def merge_arrays(left, right, schema)
    items_schema = schema.fetch("items", {})
    values = Array(left) + Array(right)
    seen = {}

    values.filter_map do |value|
      compacted = compact_value(value, items_schema)
      next if blank_value?(compacted)

      fingerprint = JSON.generate(canonicalize(compacted))
      next if seen[fingerprint]

      seen[fingerprint] = true
      compacted
    end
  end

  def compact_value(value, schema)
    case value
    when Hash
      value.stringify_keys.to_h do |key, child|
        child_schema = schema.fetch("properties", {}).fetch(key, {})
        [ key, compact_value(child, child_schema) ]
      end.reject { |_key, child| blank_value?(child) }
    when Array
      value.map { |child| compact_value(child, schema.fetch("items", {})) }
        .reject { |child| blank_value?(child) }
    else
      value
    end
  end

  def schema_type(schema, left, right)
    type = schema["type"]
    type = type.find { |candidate| candidate != "null" } if type.is_a?(Array)
    type || ("object" if left.is_a?(Hash) || right.is_a?(Hash)) || ("array" if left.is_a?(Array) || right.is_a?(Array))
  end

  def blank_value?(value)
    value.nil? || value == "" || value == [] || value == {}
  end

  def canonicalize(value)
    case value
    when Hash then value.sort.to_h.transform_values { |child| canonicalize(child) }
    when Array then value.map { |child| canonicalize(child) }
    else value
    end
  end
end
