class DocumentExtractionAgent < LlmWorkflowAgent
  inputs :document_name, :source_label, :source_tool, :extraction_schema
  tools { [ source_tool ] }
  schema do
    { name: "document_extraction", schema: extraction_schema, strict: false }
  end

  instructions do
    <<~PROMPT
      You extract structured data from documents. You must call the source tool before responding.
      Extract only facts explicitly supported by #{source_label}. Never guess or copy examples from field
      descriptions. For fields absent from this source, use null, an empty string, an empty object, or an
      empty array as permitted by the schema. Preserve source order and wording where practical.

      Document: #{document_name}
    PROMPT
  end
end
