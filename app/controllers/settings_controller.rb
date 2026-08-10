class SettingsController < ApplicationController
  def show
    load_settings
  end

  def update
    LlmModelCatalog.update_defaults!(workflow_defaults_params)
    redirect_to settings_path, notice: "Workflow default models updated."
  rescue ArgumentError => error
    redirect_to settings_path, alert: error.message
  end

  private

  def load_settings
    @agent_models = LlmModelCatalog.options(capability: :function_calling)
    @structured_models = LlmModelCatalog.options(capability: :structured_output)
    @selectable_models = (@agent_models + @structured_models).uniq(&:key)
      .sort_by { |model| [ model.provider, -(model.created_at&.to_i || 0), model.name ] }
    @models_by_provider = @selectable_models.group_by(&:provider)
    @default_keys = LlmModelCatalog::DEFAULTS.keys.to_h do |context|
      [ context, LlmModelCatalog.default(context) ]
    end
    @defaults = @default_keys.transform_values { |key| LlmModelCatalog.find(key) }
    @latest_model_release = @selectable_models.filter_map(&:created_at).max
  end

  def workflow_defaults_params
    params.require(:workflow_defaults).permit(*LlmModelCatalog::DEFAULTS.keys)
  end
end
