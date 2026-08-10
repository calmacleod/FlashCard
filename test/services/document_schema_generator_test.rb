require "test_helper"

class DocumentSchemaGeneratorTest < ActiveSupport::TestCase
  FakeResponse = Data.define(:content)

  class FakeChat
    attr_reader :thinking, :prompt

    def with_thinking(**thinking)
      @thinking = thinking
      self
    end

    def with_schema(_schema) = self

    def ask(prompt)
      @prompt = prompt
      FakeResponse.new({
        "schema_json" => {
          type: "object",
          properties: {
            rules: {
              type: "array",
              items: { type: "object", properties: { text: { type: "string" } } }
            }
          }
        }.to_json
      })
    end
  end

  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-schema-test", name: "Schema Test",
      capabilities: %w[structured_output reasoning]
    )
    @document = Document.new(name: "Rules")
    @document.file.attach(io: StringIO.new("Rule 1: Play fairly."), filename: "rules.txt", content_type: "text/plain")
    @document.save!
  end

  test "generates a strict object schema from document content" do
    fake_chat = FakeChat.new
    original_chat = RubyLLM.method(:chat)
    RubyLLM.define_singleton_method(:chat) { |**_args| fake_chat }
    begin
      schema = DocumentSchemaGenerator.generate(
        @document, model_key: "openai:gpt-schema-test", effort: "low"
      )

      assert_equal false, schema["additionalProperties"]
      assert_equal false, schema.dig("properties", "rules", "items", "additionalProperties")
      assert_equal({ effort: "low" }, fake_chat.thinking)
      assert_includes fake_chat.prompt, "root object with no more than 6 properties"
      assert_includes fake_chat.prompt, "one complete body/text field"
      assert_includes fake_chat.prompt, "Keep nesting to root -> record -> simple scalar arrays"
    ensure
      RubyLLM.define_singleton_method(:chat, original_chat)
    end
  end
end
