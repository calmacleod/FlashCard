require "test_helper"

class DocumentDataExtractorTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:content)

  class FakeChat
    attr_reader :schema, :thinking, :prompts, :instructions, :tools

    def initialize(responses)
      @responses = responses
      @prompts = []
    end

    def with_thinking(**thinking)
      @thinking = thinking
      self
    end

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def with_tools(*tools)
      @tools = tools
      self
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt)
      @prompts << prompt
      FakeResponse.new(@responses.shift)
    end
  end

  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-extraction-test", name: "Extraction Test",
      capabilities: %w[structured_output function_calling reasoning]
    )
    @document = Document.new(name: "Roster")
    @document.file.attach(
      io: StringIO.new("Player: Ada\n\nNumber: 12"),
      filename: "roster.txt",
      content_type: "text/plain"
    )
    @document.save!
    @schema = {
      "type" => "object",
      "properties" => {
        "players" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => { "name" => { "type" => "string" } }
          }
        }
      }
    }
  end

  test "extracts with the generated schema and selected model" do
    fake_chat = FakeChat.new([ { "players" => [ { "name" => "Ada" } ] } ])
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) do |model:, provider:|
      raise "wrong model" unless model == "gpt-extraction-test" && provider == :openai
      fake_chat
    end

    begin
      progress = []
      result = DocumentDataExtractor.extract(
        @document,
        schema: @schema,
        model_key: "openai:gpt-extraction-test",
        thinking: { effort: "low" },
        on_progress: ->(done, total) { progress << [ done, total ] }
      )

      assert_equal({ "players" => [ { "name" => "Ada" } ] }, result)
      assert_equal @schema, fake_chat.schema[:schema]
      assert_equal false, fake_chat.schema[:strict]
      assert_equal({ effort: "low" }, fake_chat.thinking)
      assert_equal 1, fake_chat.tools.size
      assert_equal "Source chunk 1 of 1\n\nPlayer: Ada\n\nNumber: 12", fake_chat.tools.first.execute
      refute_includes fake_chat.prompts.first, "Player: Ada"
      assert_equal [ [ 0, 1 ], [ 1, 1 ] ], progress
    ensure
      RubyLLM.define_singleton_method(:chat, original_chat)
    end
  end

  test "extracts multiple chunks in parallel while preserving result order" do
    long_text = [ "Ada " * 3_000, "Grace " * 3_000, "Linus " * 3_000 ].join("\n\n")
    @document.file.purge
    @document.file.attach(
      io: StringIO.new(long_text), filename: "large-roster.txt", content_type: "text/plain"
    )
    thread_ids = []
    lock = Mutex.new
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) do |**_args|
      Class.new do
        define_method(:with_instructions) { |_instructions| self }
        define_method(:with_tools) { |*_tools| self }
        define_method(:with_schema) { |_schema| self }
        define_method(:ask) do |_prompt|
          lock.synchronize { thread_ids << Thread.current.object_id }
          sleep 0.05
          FakeResponse.new({ "players" => [] })
        end
      end.new
    end

    begin
      progress = []
      DocumentDataExtractor.extract(
        @document, schema: @schema, model_key: "openai:gpt-extraction-test",
        on_progress: ->(done, total) { progress << [ done, total ] }
      )

      assert_operator thread_ids.uniq.length, :>, 1
      assert_equal [ 0, 3 ], progress.first
      assert_equal [ 3, 3 ], progress.last
    ensure
      RubyLLM.define_singleton_method(:chat, original_chat)
    end
  end
end
