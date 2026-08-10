class LlmWorkflowAgent < RubyLLM::Agent
  def self.build(entry:, thinking: {}, **inputs)
    new(
      model: entry.model_id,
      provider: entry.provider.to_sym,
      **inputs
    ).tap do |agent|
      agent.with_thinking(**thinking) if thinking.present?
    end
  end
end
