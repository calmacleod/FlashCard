RubyLLM.configure do |config|
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", "dummy-key")
  config.openai_use_system_role = true
  config.logger = Rails.logger

  config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
