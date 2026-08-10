require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-document-test", name: "Document Test",
      capabilities: %w[structured_output reasoning]
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
end
