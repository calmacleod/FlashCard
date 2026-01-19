require "net/http"
require "json"

class OllamaClient
  Response = Data.define(:text)
  Embedding = Data.define(:vector)
  RequestError = Class.new(StandardError)

  def initialize(base_url: "http://localhost:11434")
    @base_url = base_url
  end

  # Text generation (legacy endpoint).
  # Prefer #chat for structured outputs via JSON schema `format`.
  def generate(prompt:, model:, temperature: 0.2, format: nil, options: {})
    uri = URI.join(@base_url, "/api/generate")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    payload = {
      model: model,
      prompt: prompt,
      temperature: temperature,
      stream: false,
      options: options
    }
    payload[:format] = format if format
    request.body = JSON.dump(payload)

    response = http_post(uri, request)

    ensure_success!(response)
    payload = JSON.parse(response.body)
    Response.new(payload.fetch("response"))
  rescue JSON::ParserError => error
    raise RequestError, "Ollama returned invalid JSON: #{error.message}"
  rescue Errno::ECONNREFUSED, SocketError => error
    raise RequestError, "Unable to reach Ollama at #{@base_url}: #{error.message}"
  end

  # Chat endpoint (recommended for structured outputs per Ollama docs).
  # messages: [{role:"user"|"system"|"assistant", content:"..."}]
  # format: "json" OR a JSON schema object (Hash) to constrain output.
  def chat(messages:, model:, temperature: 0.2, format: nil, options: {})
    uri = URI.join(@base_url, "/api/chat")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    payload = {
      model: model,
      messages: messages,
      temperature: temperature,
      stream: false,
      options: options
    }
    payload[:format] = format if format
    request.body = JSON.dump(payload)

    response = http_post(uri, request)

    ensure_success!(response)
    payload = JSON.parse(response.body)
    message = payload.fetch("message")
    Response.new(message.fetch("content"))
  rescue JSON::ParserError => error
    raise RequestError, "Ollama returned invalid JSON: #{error.message}"
  rescue Errno::ECONNREFUSED, SocketError => error
    raise RequestError, "Unable to reach Ollama at #{@base_url}: #{error.message}"
  end

  def models
    uri = URI.join(@base_url, "/api/tags")
    response = Net::HTTP.get_response(uri)

    ensure_success!(response)
    payload = JSON.parse(response.body)
    payload.fetch("models", []).map { |model| model.fetch("name") }.sort
  rescue JSON::ParserError => error
    raise RequestError, "Ollama returned invalid JSON: #{error.message}"
  rescue Errno::ECONNREFUSED, SocketError => error
    raise RequestError, "Unable to reach Ollama at #{@base_url}: #{error.message}"
  end

  def embed(text:, model:)
    uri = URI.join(@base_url, "/api/embeddings")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.dump(
      model: model,
      prompt: text
    )

    response = Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(request)
    end

    ensure_success!(response)
    payload = JSON.parse(response.body)
    Embedding.new(payload.fetch("embedding"))
  rescue JSON::ParserError => error
    raise RequestError, "Ollama returned invalid JSON: #{error.message}"
  rescue Errno::ECONNREFUSED, SocketError => error
    raise RequestError, "Unable to reach Ollama at #{@base_url}: #{error.message}"
  end

  private

  def http_post(uri, request)
    Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.open_timeout = Integer(ENV.fetch("OLLAMA_OPEN_TIMEOUT", "5"))
      http.read_timeout = Integer(ENV.fetch("OLLAMA_READ_TIMEOUT", "300"))
      http.write_timeout = Integer(ENV.fetch("OLLAMA_WRITE_TIMEOUT", "30")) if http.respond_to?(:write_timeout=)
      http.request(request)
    end
  end

  def ensure_success!(response)
    return if response.is_a?(Net::HTTPSuccess)

    details =
      begin
        JSON.parse(response.body.to_s).fetch("error")
      rescue JSON::ParserError, KeyError
        response.body.to_s
      end

    details = details.to_s.strip
    details = details[0, 500] if details.length > 500

    message = +"Ollama request failed (#{response.code})"
    message << ": #{details}" unless details.empty?

    raise RequestError, message
  end
end
