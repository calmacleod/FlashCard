require "test_helper"

class ExtractionResultMergerTest < ActiveSupport::TestCase
  test "merges nested values and deduplicates repeated records" do
    schema = {
      "type" => "object",
      "properties" => {
        "title" => { "type" => "string" },
        "records" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => { "name" => { "type" => "string" } }
          }
        }
      }
    }
    results = [
      { "title" => "", "records" => [ { "name" => "One" } ] },
      { "title" => "Example", "records" => [ { "name" => "One" }, { "name" => "Two" } ] }
    ]

    merged = ExtractionResultMerger.merge(results, schema:)

    assert_equal "Example", merged["title"]
    assert_equal [ { "name" => "One" }, { "name" => "Two" } ], merged["records"]
  end
end
