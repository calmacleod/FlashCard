class DocumentExtractionsController < ApplicationController
  before_action :set_document
  before_action :set_extraction, only: %i[show download]

  def create
    schema = @document.extraction_schema_hash
    return redirect_to(@document, alert: "Generate a valid extraction schema first.") unless schema
    return redirect_to(@document, alert: "An extraction is already running.") if @document.extractions.active.exists?

    settings = @document.llm_setting(:extraction)
    entry = LlmModelCatalog.find!(settings.fetch("model"), capability: :structured_output)
    thinking = LlmModelCatalog.thinking_params(
      entry, effort: settings["effort"], budget: settings["budget"]
    )
    extraction = @document.extractions.create!(
      schema_snapshot: schema,
      model_key: entry.key,
      thinking:
    )
    DocumentExtractionJob.perform_later(extraction.id)

    redirect_to @document, notice: "Document extraction started."
  end

  def show
    return redirect_to(@document, alert: "Extraction has not completed.") unless @extraction.completed?

    @extraction_markdown = ExtractionMarkdownRenderer.render(
      @extraction.result, schema: @extraction.schema_snapshot
    )
  end

  def download
    return redirect_to(@document, alert: "Extraction has not completed.") unless @extraction.completed?

    respond_to do |format|
      format.json do
        send_data JSON.pretty_generate(@extraction.result),
          filename: filename("json"), type: "application/json"
      end
      format.csv do
        send_data ExtractionResultCsv.generate(@extraction.result),
          filename: filename("csv"), type: "text/csv"
      end
    end
  end

  private

  def set_document
    @document = Document.find(params[:document_id])
  end

  def set_extraction
    @extraction = @document.extractions.find(params[:id])
  end

  def filename(extension)
    stem = @document.name.parameterize.presence || "document"
    "#{stem}-extraction-#{@extraction.id}.#{extension}"
  end
end
