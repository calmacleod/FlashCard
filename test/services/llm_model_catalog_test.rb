require "test_helper"

class LlmModelCatalogTest < ActiveSupport::TestCase
  setup do
    @openai = Model.create!(
      provider: "openai", model_id: "gpt-5.6-test", name: "GPT Test",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: 1.day.ago
    )
    @gemini = Model.create!(
      provider: "gemini", model_id: "gemini-2.5-test", name: "Gemini Test",
      capabilities: %w[structured_output reasoning], model_created_at: Time.current
    )
  end

  test "filters models by required capability" do
    options = LlmModelCatalog.options(capability: :function_calling)

    assert_includes options.map(&:key), "openai:gpt-5.6-test"
    refute_includes options.map(&:key), "gemini:gemini-2.5-test"
  end

  test "requires every capability for agentic document workflows" do
    options = LlmModelCatalog.options(capability: LlmModelCatalog::DOCUMENT_WORKFLOW_CAPABILITIES)

    assert_includes options.map(&:key), "openai:gpt-5.6-test"
    refute_includes options.map(&:key), "gemini:gemini-2.5-test"
  end

  test "uses provider-specific thinking conventions" do
    config = LlmModelCatalog.thinking_configuration("openai:gpt-5.6-test")
    assert_equal "effort", config[:mode]
    assert_includes config[:efforts], "max"
    refute_includes config[:efforts], "minimal"
    assert_equal({ effort: "max" }, LlmModelCatalog.thinking_params("openai:gpt-5.6-test", effort: "max"))
    assert_equal({ budget: 2_000 }, LlmModelCatalog.thinking_params("gemini:gemini-2.5-test", budget: "2000"))
    assert_empty LlmModelCatalog.thinking_params("gemini:gemini-2.5-test", budget: "999999")
  end

  test "disables GPT 5.6 reasoning when function tools use Chat Completions" do
    config = LlmModelCatalog.tool_thinking_configuration("openai:gpt-5.6-test")

    assert_equal "effort", config[:mode]
    assert_equal [ "none" ], config[:efforts]
    assert_includes config[:hint], "Chat Completions"
    assert_equal({ effort: "none" },
      LlmModelCatalog.tool_thinking_params("openai:gpt-5.6-test", effort: "high"))
    assert_empty LlmModelCatalog.tool_thinking_params("openai:gpt-5.6-test")
  end

  test "persists editable workflow defaults" do
    LlmModelCatalog.update_defaults!(
      agent: "openai:gpt-5.6-test",
      schema: "openai:gpt-5.6-test",
      extraction: "openai:gpt-5.6-test",
      flashcards: "openai:gpt-5.6-test"
    )

    assert_equal "openai:gpt-5.6-test", LlmModelCatalog.default(:extraction)
    assert_equal "openai:gpt-5.6-test",
      ApplicationSetting.value_for("workflow_defaults").fetch("flashcards")
  end


  test "hides local, stale, and unrelated model families" do
    Model.create!(
      provider: "ollama", model_id: "qwen3:latest", name: "Qwen",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: Time.current
    )
    Model.create!(
      provider: "openai", model_id: "gpt-5.3-old", name: "Old GPT",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: Time.current
    )
    Model.create!(
      provider: "gemini", model_id: "gemma-4-test", name: "Gemma",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: Time.current
    )

    keys = LlmModelCatalog.options(capability: :structured_output).map(&:key)

    refute_includes keys, "ollama:qwen3:latest"
    refute_includes keys, "openai:gpt-5.3-old"
    refute_includes keys, "gemini:gemma-4-test"
  end
end
