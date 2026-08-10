class ModelRegistryRefresher
  Result = Data.define(:model_count, :selectable_count, :latest_release)

  def self.call
    RubyLLM.models.refresh!(remote_only: true)
    Model.save_to_database
    Model.touch_all

    unless Model.exists?(provider: "openai", model_id: "gpt-5.6")
      raise RubyLLM::ModelRegistryError, "The refreshed registry does not include GPT-5.6"
    end

    Result.new(
      model_count: Model.count,
      selectable_count: %i[function_calling structured_output].flat_map do |capability|
        LlmModelCatalog.options(capability:).map(&:key)
      end.uniq.size,
      latest_release: Model.maximum(:model_created_at)
    )
  end
end
