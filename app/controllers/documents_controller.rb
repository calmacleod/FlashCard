class DocumentsController < ApplicationController
  before_action :set_document, only: [ :show, :edit, :update, :destroy, :generate_schema ]
  before_action :load_model_options, only: [ :new, :create, :edit, :update ]

  def index
    @documents = Document.with_attached_file.order(created_at: :desc)
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    @document.update_llm_settings(llm_settings_params)
    if @document.save
      enqueue_schema_generation
      redirect_to @document, notice: "Document uploaded successfully. Its extraction schema is being generated."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    @document.assign_attributes(document_schema_params)
    @document.update_llm_settings(llm_settings_params)
    if @document.save
      redirect_to @document, notice: "Document settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def generate_schema
    enqueue_schema_generation
    redirect_to @document, notice: "Schema generation started."
  end

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

  def document_schema_params
    params.require(:document).permit(:extraction_schema)
  end

  def llm_settings_params
    params.fetch(:document, {}).fetch(:llm_settings, {}).permit(
      schema: %i[model effort budget],
      extraction: %i[model effort budget],
      flashcards: %i[model effort budget]
    )
  end

  def load_model_options
    current = @document&.llm_setting(:schema)&.fetch("model", nil)
    @structured_models = LlmModelCatalog.options(capability: :structured_output, current:)
  end

  def enqueue_schema_generation
    @document.update!(schema_generation_status: "queued", schema_generation_error: nil)
    DocumentSchemaGenerationJob.perform_later(@document.id)
  end
end
