require "ruby_llm"
require "ruby_llm/schema"

# RubyLLM configuration
#
# We connect RubyLLM's :openai provider to Ollama via Ollama's OpenAI-compatible API.
# RubyLLM docs:
# - Configuration: https://rubyllm.com/configuration/
# - Chat: https://rubyllm.com/chat/
# - Embeddings: https://rubyllm.com/embeddings/
RubyLLM.configure do |config|
  config.model_registry_file = "config/models.json"

  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY")
  config.openai_api_base = ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434/v1")
  config.openai_api_key = ENV.fetch("OLLAMA_API_KEY", "dummy-key")
  config.openai_use_system_role = true

  # Optional defaults you can set via env (applies to RubyLLM.chat / RubyLLM.embed convenience methods)
  # config.default_model = ENV["RUBYLLM_DEFAULT_MODEL"] if ENV["RUBYLLM_DEFAULT_MODEL"].present?
  c# onfig.default_embedding_model = ENV["RUBYLLM_DEFAULT_EMBEDDING_MODEL"] if ENV["RUBYLLM_DEFAULT_EMBEDDING_MODEL"].present?

  config.logger = Rails.logger
end
