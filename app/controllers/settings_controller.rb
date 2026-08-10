class SettingsController < ApplicationController
  def show
    @agent_models = LlmModelCatalog.options(capability: :function_calling)
    @structured_models = LlmModelCatalog.options(capability: :structured_output)
    @selectable_models = (@agent_models + @structured_models).uniq(&:key)
      .sort_by { |model| [ model.provider, -(model.created_at&.to_i || 0), model.name ] }
    @models_by_provider = @selectable_models.group_by(&:provider)
    @defaults = LlmModelCatalog::DEFAULTS.transform_values { |key| LlmModelCatalog.find(key) }
    @latest_model_release = @selectable_models.filter_map(&:created_at).max
  end
end
