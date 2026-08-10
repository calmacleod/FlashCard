class ExtractionViewer
  PER_PAGE = 25

  Field = Data.define(:name, :value, :schema) do
    def label = schema["title"].presence || name.to_s.humanize
    def missing? = value.nil? || value.respond_to?(:empty?) && value.empty?
  end

  attr_reader :result, :schema, :records, :record_schema, :collection_name

  def initialize(result:, schema:)
    @result = result.to_h.deep_stringify_keys
    @schema = schema.to_h.deep_stringify_keys
    @collection_name, collection_schema = find_primary_collection
    @records = collection_name ? Array(@result[collection_name]) : []
    @record_schema = collection_schema&.fetch("items", {}) || {}
  end

  def title
    schema["title"].presence || "Schema-guided extraction"
  end

  def collection_label
    collection_name&.humanize || "Records"
  end

  def top_level_field_count
    schema.fetch("properties", {}).size
  end

  def missing_required_count
    count_missing(result, schema)
  end

  def document_fields
    fields_for(result, schema).reject { |field| field.name == collection_name }
  end

  def fields_for(value, value_schema)
    object = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    properties = value_schema.to_h.deep_stringify_keys.fetch("properties", {})
    keys = properties.keys | object.keys
    keys.map { |name| Field.new(name:, value: object[name], schema: properties.fetch(name, {})) }
  end

  def record_title(record, index)
    object = record.to_h.deep_stringify_keys
    candidates = %w[title heading name article_title section_title rule_title]
    candidates.concat(object.keys.grep(/(?:title|heading|name)\z/))
    candidates.concat(%w[section article rule_number reference id])
    value = candidates.filter_map { |key| scalar_preview(object[key]) }.first
    value ||= object.values.filter_map { |item| scalar_preview(item) }.first
    value.present? ? value : "#{collection_label.singularize} #{index + 1}"
  end

  def record_completion(record)
    properties = record_schema.fetch("properties", {})
    present = properties.keys.count { |key| present_value?(record.to_h.deep_stringify_keys[key]) }
    [ present, properties.size ]
  end

  def page(number)
    requested = Integer(number, exception: false).to_i
    [ requested, 1 ].max.clamp(1, total_pages)
  end

  def records_on_page(number)
    records.slice((page(number) - 1) * PER_PAGE, PER_PAGE) || []
  end

  def total_pages
    [ (records.size.to_f / PER_PAGE).ceil, 1 ].max
  end

  private

  def find_primary_collection
    schema.fetch("properties", {}).find do |name, property_schema|
      property_schema["type"] == "array" &&
        property_schema.dig("items", "type") == "object" &&
        result[name].is_a?(Array)
    end
  end

  def count_missing(value, value_schema)
    case value_schema["type"]
    when "object"
      object = value.is_a?(Hash) ? value.deep_stringify_keys : {}
      properties = value_schema.fetch("properties", {})
      missing = Array(value_schema["required"]).count { |key| !present_value?(object[key]) }
      missing + properties.sum { |key, child_schema| count_missing(object[key], child_schema) }
    when "array"
      Array(value).sum { |item| count_missing(item, value_schema.fetch("items", {})) }
    else
      0
    end
  end

  def present_value?(value)
    !(value.nil? || value.respond_to?(:empty?) && value.empty?)
  end

  def scalar_preview(value)
    return unless value.is_a?(String) || value.is_a?(Numeric)

    text = value.to_s.squish
    text.truncate(90) if text.present?
  end
end
