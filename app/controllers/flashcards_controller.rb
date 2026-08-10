class FlashcardsController < ApplicationController
  before_action :set_document, except: [ :index ]

  def index
    @flashcards_by_document = Document.joins(:flashcards).includes(:flashcards).distinct
  end

  def show
    @flashcards = @document.flashcards.ordered
  end

  def create
    if @document.processing_status == "processing"
      redirect_to document_path(@document), notice: "Generation already in progress."
      return
    end

    unless @document.latest_completed_extraction
      redirect_to document_path(@document), alert: "Extract document data before generating flashcards."
      return
    end

    persona = FlashcardPersona.find!(params[:persona].presence || @document.flashcard_persona)
    @document.update!(
      flashcard_persona: persona.key,
      processing_status: "processing",
      processing_error: nil,
      processing_progress: { stage: "queued", persona: persona.key }.to_json
    )
    FlashcardGenerationJob.perform_later(@document.id, persona.key)
    redirect_to document_path(@document), notice: "Flashcard generation started with the #{persona.name} persona."
  rescue ArgumentError => error
    redirect_to document_path(@document), alert: error.message
  end

  private

  def set_document
    @document = Document.find(params[:document_id])
  end
end
