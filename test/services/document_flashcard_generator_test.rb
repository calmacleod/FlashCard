require "test_helper"

class DocumentFlashcardGeneratorTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:content)

  class FakeChat
    attr_reader :prompt, :thinking, :instructions, :tools, :schema

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def with_tools(*tools)
      @tools = tools
      self
    end

    def with_thinking(**thinking)
      @thinking = thinking
      self
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def ask(prompt)
      @prompt = prompt
      FakeResponse.new({
        "cards" => [
          { "reference" => "Rule 1", "front" => "When does play begin?", "back" => "On the whistle." },
          { "reference" => "Rule 1", "front" => "When does play begin?", "back" => "On the whistle." }
        ]
      })
    end
  end

  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-5.6-luna", name: "Flashcard Test",
      capabilities: %w[structured_output function_calling reasoning]
    )
    document = Document.new(name: "Rules")
    document.file.attach(io: StringIO.new("Rules"), filename: "rules.txt", content_type: "text/plain")
    document.save!
    @extraction = document.extractions.create!(
      status: "completed",
      schema_snapshot: {
        "type" => "object",
        "properties" => {
          "articles" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "title" => { "type" => "string" },
                "body" => { "type" => "string" }
              }
            }
          }
        }
      },
      result: { "articles" => [ { "title" => "Kickoff", "body" => "Play begins on the whistle." } ] },
      model_key: "openai:gpt-5.6-luna"
    )
  end

  test "uses the selected persona and removes duplicate cards" do
    fake_chat = FakeChat.new
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) do |model:, provider:|
      raise "wrong model" unless model == "gpt-5.6-luna" && provider == :openai
      fake_chat
    end

    begin
      progress = []
      cards = DocumentFlashcardGenerator.generate(
        @extraction,
        model_key: "openai:gpt-5.6-luna",
        persona_key: "football_rules",
        thinking: { effort: "high" },
        on_progress: ->(*values) { progress << values }
      )

      assert_equal 1, cards.length
      assert_equal "When does play begin?", cards.first.front
      assert_includes fake_chat.instructions, "Persona: Football rules"
      assert_includes fake_chat.instructions, "expert football rules educator"
      assert_equal DocumentFlashcardAgent::ResponseSchema, fake_chat.schema
      assert_equal 1, fake_chat.tools.size
      assert_includes fake_chat.tools.first.execute, "Play begins on the whistle"
      refute_includes fake_chat.prompt, "Play begins on the whistle."
      assert_equal({ effort: "none" }, fake_chat.thinking)
      assert_equal [ 1, 1, 1 ], progress.last
    ensure
      RubyLLM.define_singleton_method(:chat, original_chat)
    end
  end
end
