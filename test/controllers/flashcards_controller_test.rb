require "test_helper"

class FlashcardsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-flashcards-controller", name: "Flashcards Controller",
      capabilities: %w[structured_output]
    )
    @document = Document.new(name: "Handbook")
    @document.file.attach(io: StringIO.new("Handbook"), filename: "handbook.txt", content_type: "text/plain")
    @document.update_llm_settings(
      "flashcards" => { "model" => "openai:gpt-flashcards-controller" }
    )
    @document.save!
  end

  test "enqueues persona-based generation from a completed extraction" do
    @document.extractions.create!(
      status: "completed", schema_snapshot: { "type" => "object", "properties" => {} },
      result: { "title" => "Handbook" }, model_key: "openai:gpt-flashcards-controller"
    )

    assert_enqueued_with(job: FlashcardGenerationJob, args: [ @document.id, "practical_application" ]) do
      post document_flashcards_path(@document), params: { persona: "practical_application" }
    end

    assert_redirected_to @document
    assert_equal "processing", @document.reload.processing_status
    assert_equal "practical_application", @document.flashcard_persona
  end

  test "requires extracted data before generating cards" do
    assert_no_enqueued_jobs do
      post document_flashcards_path(@document), params: { persona: "generalist" }
    end

    assert_redirected_to @document
    assert_equal "Extract document data before generating flashcards.", flash[:alert]
  end
end
