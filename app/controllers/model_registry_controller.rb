class ModelRegistryController < ApplicationController
  def refresh
    result = ModelRegistryRefresher.call
    redirect_back(
      fallback_location: root_path,
      notice: "Model registry updated: #{result.selectable_count} current models available in Settings."
    )
  rescue RubyLLM::ModelRegistryError, Faraday::Error => error
    redirect_back(
      fallback_location: root_path,
      alert: "Model registry update failed: #{error.message}"
    )
  end
end
