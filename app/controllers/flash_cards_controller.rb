require "fileutils"

class FlashCardsController < ApplicationController
  def new
    prepare_form_data
  end

  def show
    @flash_card_request = FlashCardRequest.find(params[:id])
    @prompt_text = @flash_card_request.prompt_text.presence || reconstruct_prompt_text(@flash_card_request)

    respond_to do |format|
      format.html
      format.csv do
        unless @flash_card_request.status == "completed" && @flash_card_request.response_text.present?
          return head :unprocessable_entity
        end

        pdf_filename = @flash_card_request.pdf_filename.to_s
        base = File.basename(pdf_filename, File.extname(pdf_filename)).strip
        base = "anki-cards" if base.empty?
        base = base.parameterize(separator: "-").presence || "anki-cards"
        timestamp = @flash_card_request.created_at&.strftime("%Y%m%d-%H%M") || Time.current.strftime("%Y%m%d-%H%M")
        filename = "#{base}-anki-cards-#{timestamp}-#{@flash_card_request.id}.csv"
        send_data(
          @flash_card_request.response_text,
          filename:,
          type: "text/csv; charset=utf-8",
          disposition: "attachment"
        )
      end
      format.json do
        render json: {
          id: @flash_card_request.id,
          status: @flash_card_request.status,
          progress: @flash_card_request.progress,
          current_step: @flash_card_request.current_step,
          model: @flash_card_request.model,
          pdf_filename: @flash_card_request.pdf_filename,
          log_tail: @flash_card_request.log_text.to_s[-10_000, 10_000].to_s,
          prompt_present: @prompt_text.present?
        }
      end
    end
  end

  def create
    uploaded_pdf = params[:pdf]

    unless uploaded_pdf
      flash.now[:alert] = "Please upload a PDF."
      prepare_form_data
      return render :new, status: :unprocessable_entity
    end

    guidance = params[:guidance].to_s.strip
    notes = params[:notes].to_s.strip
    model = params[:model].presence || default_model
    embedding_model = params[:embedding_model].presence || default_embedding_model

    pdf_path = persist_uploaded_pdf(uploaded_pdf)
    request = persist_request!(
      pdf_filename: uploaded_pdf.original_filename,
      pdf_path:,
      guidance:,
      notes:,
      model:,
      embedding_model:
    )

    FlashCardGenerationJob.perform_later(request.id)

    redirect_to flash_card_path(request)
  rescue PdfTextExtractor::ExtractionError, OllamaClient::RequestError,
         ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError => error
    flash.now[:alert] = error.message
    prepare_form_data
    render :new, status: :unprocessable_entity
  end

  def retry
    request = FlashCardRequest.find(params[:id])

    unless request.pdf_path.present? && File.exist?(request.pdf_path)
      flash[:alert] = "Original PDF is missing from storage; cannot retry."
      return redirect_to flash_card_path(request)
    end

    request.update!(
      status: "queued",
      progress: 0,
      current_step: "Queued for retry",
      error_message: nil,
      response_text: nil,
      vector_path: nil,
      log_text: nil,
      prompt_text: nil
    )
    request.append_log!("Retry requested")

    FlashCardGenerationJob.perform_later(request.id)
    redirect_to flash_card_path(request)
  end

  private

  def default_model
    ENV.fetch("OLLAMA_GENERATION_MODEL") do
      OllamaClient.new.models.first || "llama3.2"
    end
  rescue OllamaClient::RequestError
    "llama3.2"
  end

  def default_embedding_model
    ENV.fetch("OLLAMA_EMBEDDING_MODEL", "nomic-embed-text")
  end

  def prepare_form_data
    @default_model = default_model
    @available_models = fetch_available_models
    @recent_requests = load_recent_requests
  end

  def fetch_available_models
    OllamaClient.new.models
  rescue OllamaClient::RequestError => error
    flash.now[:alert] = error.message
    []
  end

  def load_recent_requests
    FlashCardRequest.order(created_at: :desc).limit(8)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    []
  end

  def persist_request!(pdf_filename:, pdf_path:, guidance:, notes:, model:, embedding_model:)
    FlashCardRequest.create!(
      pdf_filename:,
      pdf_path:,
      guidance: guidance.presence,
      notes: notes.presence,
      model:,
      embedding_model:,
      status: "queued",
      progress: 0
    )
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    flash[:alert] = "Database is not ready. Run the migrations to save requests."
    raise
  end

  def persist_uploaded_pdf(uploaded_pdf)
    uploads_dir = Rails.root.join("storage", "uploads")
    FileUtils.mkdir_p(uploads_dir)
    safe_name = File.basename(uploaded_pdf.original_filename)
    file_name = "#{SecureRandom.hex(12)}-#{safe_name}"
    path = uploads_dir.join(file_name)
    File.binwrite(path, uploaded_pdf.read)
    path.to_s
  end

  def reconstruct_prompt_text(request)
    return nil unless request.pdf_path.present? && File.exist?(request.pdf_path)

    pdf_text = PdfTextExtractor.extract(request.pdf_path)
    FlashCardPromptBuilder.build(
      pdf_text:,
      guidance: request.guidance.to_s,
      notes: request.notes.to_s
    )
  rescue PdfTextExtractor::ExtractionError
    nil
  end
end
