class DocumentDataExtractor
  MAX_CHUNK_CHARACTERS = 20_000
  MAX_CONCURRENCY = 4

  def self.extract(document, schema:, model_key:, thinking: {}, on_progress: nil)
    new(document, schema:, model_key:, thinking:, on_progress:).extract
  end

  def initialize(document, schema:, model_key:, thinking: {}, on_progress: nil)
    @document = document
    @schema = schema.deep_stringify_keys
    @entry = LlmModelCatalog.find!(model_key, capability: :structured_output)
    @thinking = thinking.symbolize_keys
    @on_progress = on_progress
  end

  def extract
    chunks = chunk(DocumentTextExtractor.extract(@document))
    raise ArgumentError, "The document contains no extractable text" if chunks.empty?

    @on_progress&.call(0, chunks.length)
    results = extract_chunks(chunks)

    ExtractionResultMerger.merge(results, schema: @schema)
  end

  private

  def extract_chunks(chunks)
    jobs = Queue.new
    outcomes = Queue.new
    chunks.each_with_index { |source, index| jobs << [ source, index ] }
    worker_count = [ chunks.length, MAX_CONCURRENCY ].min
    worker_count.times { jobs << nil }

    workers = Array.new(worker_count) do
      Thread.new do
        while (job = jobs.pop)
          source, index = job
          begin
            outcomes << [ index, extract_chunk(source, index:, total: chunks.length), nil ]
          rescue => error
            outcomes << [ index, nil, error ]
          end
        end
      end.tap { |worker| worker.report_on_exception = false }
    end

    results = Array.new(chunks.length)
    first_error = nil
    chunks.length.times do |completed|
      index, result, error = outcomes.pop
      results[index] = result
      first_error ||= error
      @on_progress&.call(completed + 1, chunks.length)
    end
    workers.each(&:join)
    raise first_error if first_error

    results
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
  end

  def extract_chunk(source, index:, total:)
    chat = RubyLLM.chat(model: @entry.model_id, provider: @entry.provider.to_sym)
    chat.with_thinking(**@thinking) if @thinking.any?
    response = chat.with_schema(
      name: "document_extraction",
      schema: @schema,
      strict: false
    ).ask(prompt(source, index:, total:))

    payload = response.content
    payload = JSON.parse(payload) if payload.is_a?(String)
    raise ArgumentError, "Extraction response must be a JSON object" unless payload.is_a?(Hash)

    payload.deep_stringify_keys
  end

  def prompt(source, index:, total:)
    <<~PROMPT
      Extract structured data from source chunk #{index + 1} of #{total} using the supplied JSON Schema.
      Include only facts explicitly supported by this chunk. Do not guess or copy examples from field
      descriptions. For fields absent from this chunk, use null, an empty string, an empty object, or an
      empty array as permitted by the schema. Preserve source order and wording where practical.

      DOCUMENT: #{@document.name}

      SOURCE CHUNK:
      #{source}
    PROMPT
  end

  def chunk(text)
    paragraphs = text.to_s.split(/\n{2,}/).map(&:strip).reject(&:empty?)
    chunks = []
    current = +""

    paragraphs.each do |paragraph|
      slices(paragraph).each do |piece|
        if current.present? && current.length + piece.length + 2 > MAX_CHUNK_CHARACTERS
          chunks << current
          current = +""
        end
        current << "\n\n" if current.present?
        current << piece
      end
    end

    chunks << current if current.present?
    chunks
  end

  def slices(text)
    return [ text ] if text.length <= MAX_CHUNK_CHARACTERS

    text.scan(/.{1,#{MAX_CHUNK_CHARACTERS}}(?:\s+|\z)/m).map(&:strip).reject(&:empty?)
  end
end
