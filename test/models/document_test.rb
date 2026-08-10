require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-document-test", name: "Document Test",
      capabilities: %w[structured_output function_calling reasoning]
    )
  end

  test "normalizes model and thinking settings" do
    document = Document.new(name: "Rules")
    document.update_llm_settings(
      "schema" => { "model" => "openai:gpt-document-test", "effort" => "medium" }
    )

    assert_equal "openai:gpt-document-test", document.llm_setting(:schema)["model"]
    assert_equal "medium", document.llm_setting(:schema)["effort"]
  end

  test "stores a compatible effort for GPT 5.6 tool workflows" do
    Model.create!(
      provider: "openai", model_id: "gpt-5.6-luna", name: "GPT 5.6 Luna",
      capabilities: %w[structured_output function_calling reasoning]
    )
    document = Document.new(name: "Rules")

    document.update_llm_settings(
      "flashcards" => { "model" => "openai:gpt-5.6-luna", "effort" => "high" }
    )

    assert_equal "none", document.llm_setting(:flashcards)["effort"]
  end

  test "requires extraction schemas to have an object root" do
    document = Document.new(name: "Rules", extraction_schema: '[{"type":"string"}]')
    document.file.attach(io: StringIO.new("Rules"), filename: "rules.txt", content_type: "text/plain")

    assert_not document.valid?
    assert_includes document.errors[:extraction_schema], "must define a JSON Schema object with properties"
  end

  test "requires a known flashcard persona" do
    document = Document.new(name: "Rules", flashcard_persona: "unknown")
    document.file.attach(io: StringIO.new("Rules"), filename: "rules.txt", content_type: "text/plain")

    assert_not document.valid?
    assert document.errors[:flashcard_persona].present?
  end
end
