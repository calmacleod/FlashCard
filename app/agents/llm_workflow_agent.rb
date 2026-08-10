class LlmWorkflowAgent < RubyLLM::Agent
  def self.build(entry:, thinking: {}, **inputs)
    thinking = LlmModelCatalog.normalize_tool_thinking(entry, thinking)
    new(
      model: entry.model_id,
      provider: entry.provider.to_sym,
      **inputs
    ).tap do |agent|
      agent.with_thinking(**thinking) if thinking.present?
    end
  end
end
