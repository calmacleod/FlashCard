require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows application settings" do
    get settings_url

    assert_response :success
    assert_select "h1", "Settings"
    assert_select "form[action='#{refresh_model_registry_path}']"
    assert_select "form[action='#{settings_path}'] select", count: 4
  end

  test "updates default models for every workflow step" do
    model = Model.create!(
      provider: "openai", model_id: "gpt-5.6-settings", name: "Settings Test",
      capabilities: %w[function_calling structured_output], model_created_at: Time.current
    )
    defaults = LlmModelCatalog::DEFAULTS.keys.index_with { "#{model.provider}:#{model.model_id}" }

    patch settings_path, params: { workflow_defaults: defaults }

    assert_redirected_to settings_path
    assert_equal "openai:gpt-5.6-settings", LlmModelCatalog.default(:extraction)
  end
end
