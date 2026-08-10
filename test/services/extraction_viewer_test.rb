require "test_helper"

class ExtractionViewerTest < ActiveSupport::TestCase
  setup do
    @schema = {
      "title" => "Team roster",
      "type" => "object",
      "required" => %w[season players],
      "properties" => {
        "season" => { "type" => "string" },
        "players" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "required" => %w[name notes],
            "properties" => {
              "name" => { "type" => "string" },
              "notes" => { "type" => "string" }
            }
          }
        }
      }
    }
    @result = {
      "season" => "2026",
      "players" => [ { "name" => "Ada", "notes" => "" }, { "name" => "Grace", "notes" => "Captain" } ]
    }
  end

  test "separates document fields from the primary record collection" do
    viewer = ExtractionViewer.new(result: @result, schema: @schema)

    assert_equal "Team roster", viewer.title
    assert_equal "players", viewer.collection_name
    assert_equal [ "season" ], viewer.document_fields.map(&:name)
    assert_equal 2, viewer.records.size
    assert_equal "Ada", viewer.record_title(viewer.records.first, 0)
    assert_equal [ 1, 2 ], viewer.record_completion(viewer.records.first)
    assert_equal 1, viewer.missing_required_count
  end

  test "paginates large record collections" do
    @result["players"] = 27.times.map { |index| { "name" => "Player #{index}", "notes" => "Ready" } }
    viewer = ExtractionViewer.new(result: @result, schema: @schema)

    assert_equal 2, viewer.total_pages
    assert_equal 25, viewer.records_on_page(1).size
    assert_equal "Player 25", viewer.records_on_page(2).first["name"]
    assert_equal 2, viewer.page(99)
  end

  test "prefers a descriptive record title over numeric identifiers" do
    viewer = ExtractionViewer.new(result: @result, schema: @schema)
    record = { "section_number" => 1, "article_title" => "Definitions and markings" }

    assert_equal "Definitions and markings", viewer.record_title(record, 0)
  end
end
