require "test_helper"

class FlashcardGenerationJobTest < ActiveJob::TestCase
  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-flashcard-job-test", name: "Flashcard Job Test",
      capabilities: %w[structured_output]
    )
    @document = Document.new(name: "Handbook")
    @document.file.attach(io: StringIO.new("Handbook"), filename: "handbook.txt", content_type: "text/plain")
    @document.update_llm_settings(
      "flashcards" => { "model" => "openai:gpt-flashcard-job-test" }
    )
    @document.save!
    @document.extractions.create!(
      status: "completed", schema_snapshot: { "type" => "object", "properties" => {} },
      result: { "title" => "Handbook" }, model_key: "openai:gpt-flashcard-job-test"
    )
  end

  test "replaces cards using the selected persona" do
    original_generate = DocumentFlashcardGenerator.method(:generate)
    DocumentFlashcardGenerator.define_singleton_method(:generate) do |*_args, **options|
      options[:on_progress].call(1, 1, 2)
      [
        DocumentFlashcardGenerator::Card.new(reference: "Section 1", front: "Question one?", back: "Answer one."),
        DocumentFlashcardGenerator::Card.new(reference: "", front: "Question two?", back: "Answer two.")
      ]
    end

    begin
      FlashcardGenerationJob.perform_now(@document.id, "exam_prep")
      @document.reload

      assert_equal "completed", @document.processing_status
      assert_equal "exam_prep", @document.flashcard_persona
      assert_equal [ "Question one?", "Question two?" ], @document.flashcards.ordered.pluck(:front)
      assert_equal [ 0, 1 ], @document.flashcards.ordered.pluck(:position)
    ensure
      DocumentFlashcardGenerator.define_singleton_method(:generate, original_generate)
    end
  end
end
