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
      Create a practical JSON Schema for extracting reusable structured records from this document.
      Return a root object with descriptive snake_case property names. Prefer an array of record objects
      when the source contains repeated entries. Include descriptions, mark reliably present fields as
      required, and set additionalProperties to false on every object. Do not include Markdown.

      Document name: #{@document.name}
      Description: #{@document.description.presence || "Not provided"}

      SOURCE SAMPLE:
      #{source_text.first(MAX_SOURCE_CHARACTERS)}
    PROMPT
  end

  def source_text
    @source_text ||= @document.file.blob.open do |file|
      content = if @document.file.content_type == "application/pdf"
        Pdftotext.text(file.path)
      else
        File.read(file.path, encoding: "UTF-8")
      end
      content.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
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
