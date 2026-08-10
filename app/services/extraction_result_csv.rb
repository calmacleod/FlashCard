require "csv"

class ExtractionResultCsv
  def self.generate(result)
    new(result).generate
  end

  def initialize(result)
    @result = result.to_h.deep_stringify_keys
  end

  def generate
    rows = tabular_rows
    headers = rows.flat_map(&:keys).uniq

    CSV.generate(headers: true) do |csv|
      csv << headers
      rows.each { |row| csv << headers.map { |header| serialize(row[header]) } }
    end
  end

  private

  def tabular_rows
    arrays = @result.select { |_key, value| value.is_a?(Array) && value.all? { |item| item.is_a?(Hash) } }
    return [ flatten(@result) ] unless arrays.one?

    key, records = arrays.first
    context = flatten(@result.except(key))
    records.map { |record| context.merge(flatten(record)) }
  end

  def flatten(value, prefix = nil, output = {})
    value.each do |key, child|
      path = [ prefix, key ].compact.join(".")
      if child.is_a?(Hash)
        flatten(child, path, output)
      else
        output[path] = child
      end
    end
    output
  end

  def serialize(value)
    value.is_a?(Array) || value.is_a?(Hash) ? JSON.generate(value) : value
  end
end
