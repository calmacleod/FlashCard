class DocumentSchemaGenerationJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    document = Document.find(document_id)
    document.update!(schema_generation_status: "generating", schema_generation_error: nil)
    settings = document.llm_setting(:schema)
    schema = DocumentSchemaGenerator.generate(
      document, model_key: settings.fetch("model"),
      effort: settings["effort"], budget: settings["budget"]
    )
    document.update!(
      extraction_schema: JSON.pretty_generate(schema),
      schema_generation_status: "completed", schema_generation_error: nil
    )
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{document.id}_status")
  rescue => error
    document&.update!(schema_generation_status: "failed", schema_generation_error: error.message)
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{document.id}_status") if document
    raise
  end
end
