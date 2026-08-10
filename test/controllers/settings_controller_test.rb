require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "shows application settings" do
    get settings_url

    assert_response :success
    assert_select "h1", "Settings"
    assert_select "form[action='#{refresh_model_registry_path}']"
  end
end
