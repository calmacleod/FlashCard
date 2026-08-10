require "test_helper"

class ExtractionResultCsvTest < ActiveSupport::TestCase
  test "turns a single record array into rows with document context" do
    csv = ExtractionResultCsv.generate(
      "document_name" => "Roster",
      "players" => [
        { "name" => "Ada", "tags" => [ "captain" ] },
        { "name" => "Grace", "tags" => [] }
      ]
    )
    rows = CSV.parse(csv, headers: true)

    assert_equal %w[document_name name tags], rows.headers
    assert_equal "Roster", rows.first["document_name"]
    assert_equal "Ada", rows.first["name"]
    assert_equal '["captain"]', rows.first["tags"]
  end
end
