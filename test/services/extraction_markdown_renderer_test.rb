require "test_helper"

class ExtractionMarkdownRendererTest < ActiveSupport::TestCase
  test "renders schema fields, repeated records, and missing values as markdown" do
    schema = {
      "type" => "object",
      "required" => [ "document_name", "articles" ],
      "properties" => {
        "document_name" => {
          "type" => "string",
          "description" => "Name printed on the document."
        },
        "articles" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => [ "article_number", "text" ],
            "properties" => {
              "article_number" => { "type" => "integer" },
              "article_title" => { "type" => "string" },
              "text" => { "type" => "string" },
              "references" => { "type" => "array", "items" => { "type" => "string" } }
            }
          }
        }
      }
    }
    result = {
      "articles" => [
        {
          "article_number" => 1,
          "article_title" => "Opening play",
          "text" => "Play *fairly*.",
          "references" => [ "Rule 2", "Rule 3" ]
        }
      ]
    }

    markdown = ExtractionMarkdownRenderer.render(result, schema:)

    assert_includes markdown, "## Document name \\(required\\)"
    assert_includes markdown, "**Not extracted.**"
    assert_includes markdown, "### Article 1 — Opening play"
    assert_includes markdown, "> Play \\*fairly\\*\\."
    assert_includes markdown, "- Rule 2"
  end
end
