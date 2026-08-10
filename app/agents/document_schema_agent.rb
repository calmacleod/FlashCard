class DocumentSchemaAgent < LlmWorkflowAgent
  class ResponseSchema < RubyLLM::Schema
    string :schema_json, description: "A valid JSON Schema object encoded as JSON"
  end

  inputs :document_name, :document_description, :source_tool
  tools { [ source_tool ] }
  schema ResponseSchema

  instructions do
    <<~PROMPT
      You design concise extraction schemas for human-readable documents.
      You must call the source tool before responding. Model the document, not every possible semantic detail.

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

      Document name: #{document_name}
      Description: #{document_description.presence || "Not provided"}
    PROMPT
  end
end
