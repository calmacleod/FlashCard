class FlashcardsController < ApplicationController
  before_action :set_document

  def show
    @flashcards = @document.flashcards.ordered
  end

  def create
    if @document.processing_status == "processing"
      redirect_to document_flashcards_path(@document), notice: "Generation already in progress."
      return
    end

    FlashcardGenerationJob.perform_later(@document.id)
    redirect_to document_flashcards_path(@document)
  end

  private

  def set_document
    @document = Document.find(params[:document_id])
  end
end
