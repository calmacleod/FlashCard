require "test_helper"

class DocumentTextExtractorTest < ActiveSupport::TestCase
  test "extracts and normalizes text attachments" do
    document = Document.new(name: "Notes")
    document.file.attach(
      io: StringIO.new("First line\nSecond line"),
      filename: "notes.txt",
      content_type: "text/plain"
    )
    document.save!

    assert_equal "First line\nSecond line", DocumentTextExtractor.extract(document)
  end
end
