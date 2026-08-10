require "test_helper"

class ModelRegistryRefresherTest < ActiveSupport::TestCase
  class FakeRegistry
    attr_reader :remote_only

    def refresh!(remote_only:)
      @remote_only = remote_only
    end
  end

  test "refreshes remote models and persists the Rails registry" do
    Model.create!(
      provider: "openai", model_id: "gpt-5.6", name: "GPT-5.6",
      capabilities: %w[function_calling structured_output reasoning], model_created_at: Time.current
    )
    registry = FakeRegistry.new
    original_models = RubyLLM.method(:models)
    original_save = Model.method(:save_to_database)
    persisted = false
    RubyLLM.define_singleton_method(:models) { registry }
    Model.define_singleton_method(:save_to_database) { persisted = true }

    result = ModelRegistryRefresher.call

    assert registry.remote_only
    assert persisted
    assert_operator result.model_count, :>, 0
  ensure
    RubyLLM.define_singleton_method(:models, original_models)
    Model.define_singleton_method(:save_to_database, original_save)
  end
end
