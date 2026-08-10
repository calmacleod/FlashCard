require "test_helper"

class DocumentExtractionJobTest < ActiveJob::TestCase
  setup do
    @document = Document.new(name: "Roster")
    @document.file.attach(io: StringIO.new("Ada"), filename: "roster.txt", content_type: "text/plain")
    @document.save!
    @extraction = @document.extractions.create!(
      schema_snapshot: { "type" => "object", "properties" => {} },
      model_key: "openai:test",
      thinking: {}
    )
  end

  test "persists completed extraction results" do
    original_extract = DocumentDataExtractor.method(:extract)
    DocumentDataExtractor.define_singleton_method(:extract) do |*_args, **options|
      options[:on_progress].call(1, 1)
      { "name" => "Ada" }
    end

    begin
      DocumentExtractionJob.perform_now(@extraction.id)
      @extraction.reload

      assert_equal "completed", @extraction.status
      assert_equal({ "name" => "Ada" }, @extraction.result)
      assert_equal({ "chunks_done" => 1, "chunks_total" => 1 }, @extraction.progress)
    ensure
      DocumentDataExtractor.define_singleton_method(:extract, original_extract)
    end
  end
end
