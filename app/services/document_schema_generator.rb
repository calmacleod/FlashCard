class DocumentSchemaGenerator
  MAX_SOURCE_CHARACTERS = 24_000

  class SchemaResponse < RubyLLM::Schema
    string :schema_json, description: "A valid JSON Schema object encoded as JSON"
  end

  def self.generate(document, model_key:, effort: nil, budget: nil)
    new(document, model_key:, effort:, budget:).generate
  end

  def initialize(document, model_key:, effort: nil, budget: nil)
    @document = document
    @entry = LlmModelCatalog.find!(model_key, capability: :structured_output)
    @thinking = LlmModelCatalog.thinking_params(@entry, effort:, budget:)
  end

  def generate
    chat = RubyLLM.chat(model: @entry.model_id, provider: @entry.provider.to_sym)
    chat.with_thinking(**@thinking) if @thinking.any?
    response = chat.with_schema(SchemaResponse).ask(prompt)
    payload = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    normalize_schema(JSON.parse(payload.fetch("schema_json")))
  end

  private

  def prompt
    <<~PROMPT
      Create a concise JSON Schema that preserves this document as something a person can read from
      beginning to end. Model the document, not every possible semantic detail.

      Design constraints:
      - Use a root object with no more than 6 properties.
      - Prefer one primary array of section or record objects in source order.
      - Give each repeated record a heading/title field and one complete body/text field rather than
        splitting prose into deeply nested clauses, penalties, tables, and subclauses.
      - Keep nesting to root -> record -> simple scalar arrays. Do not create nested arrays of objects
        unless the document cannot be represented accurately without one.
      - Limit repeated record objects to about 8 useful properties. Preserve source wording in the body.
      - Include source page/reference fields only when useful for checking the extraction.
      - Use descriptive snake_case names and short descriptions. Mark only reliably present fields as required.
      - Set additionalProperties to false on every object. Do not include Markdown.

      Document name: #{@document.name}
      Description: #{@document.description.presence || "Not provided"}

      SOURCE SAMPLE:
      #{source_text.first(MAX_SOURCE_CHARACTERS)}
    PROMPT
  end

  def source_text
    @source_text ||= DocumentTextExtractor.extract(@document)
  end

  def normalize_schema(schema)
    raise ArgumentError, "Generated schema must be a JSON object" unless schema.is_a?(Hash)
    raise ArgumentError, "Generated schema root must have type object" unless schema["type"] == "object"
    raise ArgumentError, "Generated schema must define properties" unless schema["properties"].is_a?(Hash)

    enforce_strict_objects(schema)
  end

  def enforce_strict_objects(value)
    case value
    when Hash
      normalized = value.transform_values { |child| enforce_strict_objects(child) }
      normalized["additionalProperties"] = false if normalized["type"] == "object"
      normalized
    when Array then value.map { |child| enforce_strict_objects(child) }
    else value
    end
  end
end
