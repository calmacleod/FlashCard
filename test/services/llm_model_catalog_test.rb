require "test_helper"

class LlmModelCatalogTest < ActiveSupport::TestCase
  setup do
    @openai = Model.create!(
      provider: "openai", model_id: "gpt-test-reasoning", name: "GPT Test",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: 1.day.ago
    )
    @gemini = Model.create!(
      provider: "gemini", model_id: "gemini-2.5-test", name: "Gemini Test",
      capabilities: %w[structured_output reasoning], model_created_at: Time.current
    )
  end

  test "filters models by required capability" do
    options = LlmModelCatalog.options(capability: :function_calling)

    assert_includes options.map(&:key), "openai:gpt-test-reasoning"
    refute_includes options.map(&:key), "gemini:gemini-2.5-test"
  end

  test "uses provider-specific thinking conventions" do
    assert_equal "effort", LlmModelCatalog.thinking_configuration("openai:gpt-test-reasoning")[:mode]
    assert_equal({ effort: "high" }, LlmModelCatalog.thinking_params("openai:gpt-test-reasoning", effort: "high"))
    assert_equal({ budget: 2_000 }, LlmModelCatalog.thinking_params("gemini:gemini-2.5-test", budget: "2000"))
    assert_empty LlmModelCatalog.thinking_params("gemini:gemini-2.5-test", budget: "999999")
  end
end
