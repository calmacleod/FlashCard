class DocumentSchemaGenerator
  MAX_SOURCE_CHARACTERS = 24_000

  def self.generate(document, model_key:, effort: nil, budget: nil)
    new(document, model_key:, effort:, budget:).generate
  end

  def initialize(document, model_key:, effort: nil, budget: nil)
    @document = document
    @entry = LlmModelCatalog.find!(model_key, capability: LlmModelCatalog::DOCUMENT_WORKFLOW_CAPABILITIES)
    @thinking = LlmModelCatalog.thinking_params(@entry, effort:, budget:)
  end

  def generate
    agent = DocumentSchemaAgent.build(
      entry: @entry,
      thinking: @thinking,
      document_name: @document.name,
      document_description: @document.description,
      source_tool: ReadWorkflowSourceTool.new(
        content: source_text.first(MAX_SOURCE_CHARACTERS),
        label: "Document source sample"
      )
    )
    response = agent.ask("Read the source sample, then return the document extraction schema.")
    payload = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    normalize_schema(JSON.parse(payload.fetch("schema_json")))
  end

  private

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
