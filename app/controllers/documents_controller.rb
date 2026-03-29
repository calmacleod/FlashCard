class DocumentsController < ApplicationController
  before_action :set_document, only: [:show, :destroy]

  def index
    @documents = Document.with_attached_file.order(created_at: :desc)
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    if @document.save
      redirect_to @document, notice: "Document uploaded successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def destroy
    @document.destroy
    redirect_to documents_path, notice: "Document deleted."
  end

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:name, :description, :file)
  end
end
