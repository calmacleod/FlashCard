require "test_helper"

class DocumentExtractionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    Model.create!(
      provider: "openai", model_id: "gpt-controller-test", name: "Controller Test",
      capabilities: %w[structured_output]
    )
    @document = Document.new(
      name: "Roster",
      extraction_schema: JSON.generate(type: "object", properties: { players: { type: "array" } })
    )
    @document.file.attach(io: StringIO.new("Ada"), filename: "roster.txt", content_type: "text/plain")
    @document.update_llm_settings(
      "extraction" => { "model" => "openai:gpt-controller-test" }
    )
    @document.save!
  end

  test "creates a schema snapshot and enqueues extraction" do
    assert_enqueued_with(job: DocumentExtractionJob) do
      post document_extractions_path(@document)
    end

    extraction = @document.extractions.last
    assert_redirected_to @document
    assert_equal @document.extraction_schema_hash, extraction.schema_snapshot
    assert_equal "openai:gpt-controller-test", extraction.model_key
  end

  test "downloads completed results as json and csv" do
    extraction = @document.extractions.create!(
      status: "completed",
      schema_snapshot: @document.extraction_schema_hash,
      result: { "players" => [ { "name" => "Ada" } ] },
      model_key: "openai:gpt-controller-test"
    )

    get download_document_extraction_path(@document, extraction, format: :json)
    assert_response :success
    assert_equal({ "players" => [ { "name" => "Ada" } ] }, JSON.parse(response.body))

    get download_document_extraction_path(@document, extraction, format: :csv)
    assert_response :success
    assert_includes response.body, "name"
    assert_includes response.body, "Ada"
  end
end
