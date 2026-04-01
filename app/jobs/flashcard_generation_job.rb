require "csv"

class FlashcardGenerationJob < ApplicationJob
  queue_as :default

  def perform(document_id)
    @document = Document.find(document_id)

    update_progress(stage: "extracting_text")

    pdf_path   = ActiveStorage::Blob.service.path_for(@document.file.blob.key)
    output_dir = Rails.root.join("output")
    FileUtils.mkdir_p(output_dir)
    stem     = @document.name.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
    csv_path = output_dir.join("#{stem}.csv").to_s
    anki_csv = output_dir.join("#{stem}_anki.csv").to_s

    # Step 1 — Process PDF into chunks
    update_progress(stage: "processing_chunks")
    RulebookProcessor.process(
      pdf_path,
      headless:      true,
      on_chunk_done: ->(done, total, articles) {
        update_progress(
          stage:             "processing_chunks",
          chunks_done:       done,
          chunks_total:      total,
          articles_extracted: articles
        )
      }
    )

    chunks_total      = RulebookChunk.for_pdf(File.expand_path(pdf_path)).completed.count
    articles_extracted = RulebookChunk.for_pdf(File.expand_path(pdf_path)).completed.sum { |c| c.units.size }

    # Step 2 — Assemble chunks into CSV
    update_progress(
      stage:             "assembling",
      chunks_total:      chunks_total,
      chunks_done:       chunks_total,
      articles_extracted: articles_extracted
    )
    RulebookAssembler.assemble(pdf_path, format: :csv, output: csv_path)

    # Step 3 — Normalize (direct mode — no LLM)
    update_progress(
      stage:             "normalizing",
      chunks_total:      chunks_total,
      chunks_done:       chunks_total,
      articles_extracted: articles_extracted
    )
    RulebookNormalizer.normalize(csv_path, model: "gpt-5.4-nano", pdf_path: pdf_path, direct: true)

    # Step 4 — Generate flashcards
    update_progress(
      stage:             "generating_flashcards",
      chunks_total:      chunks_total,
      chunks_done:       chunks_total,
      articles_extracted: articles_extracted,
      groups_total:      0,
      groups_done:       0,
      flashcards_done:   0
    )
    RulebookFlashcardGenerator.generate(
      csv_path,
      output:        anki_csv,
      on_group_done: ->(done, total, cards) {
        update_progress(
          stage:             "generating_flashcards",
          chunks_total:      chunks_total,
          chunks_done:       chunks_total,
          articles_extracted: articles_extracted,
          groups_total:      total,
          groups_done:       done,
          flashcards_done:   cards
        )
      }
    )

    # Step 5 — Index entries for RAG search
    entries_total = RulebookEntry.for_csv(csv_path).count
    update_progress(
      stage:             "indexing",
      chunks_total:      chunks_total,
      chunks_done:       chunks_total,
      articles_extracted: articles_extracted,
      entries_total:     entries_total,
      entries_indexed:   0
    )
    index_entries(csv_path, chunks_total:, articles_extracted:, entries_total:)

    # Step 6 — Import flashcards into DB
    update_progress(
      stage:             "importing",
      chunks_total:      chunks_total,
      chunks_done:       chunks_total,
      articles_extracted: articles_extracted,
      entries_total:     entries_total,
      entries_indexed:   entries_total
    )
    import_flashcards(anki_csv)

    @document.update!(processing_status: "completed")
    broadcast_status
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{@document.id}_status")
  rescue => e
    @document&.update!(processing_status: "failed", processing_error: e.message)
    broadcast_status if @document
    Turbo::StreamsChannel.broadcast_refresh_to("document_#{@document.id}_status")
    raise
  end

  private

  def update_progress(attrs)
    current = @document.processing_progress ? JSON.parse(@document.processing_progress) : {}
    merged  = current.merge(attrs.transform_keys(&:to_s))
    @document.update_columns(
      processing_status:   "processing",
      processing_progress: merged.to_json
    )
    broadcast_status
  end

  def index_entries(csv_path, chunks_total:, articles_extracted:, entries_total:)
    indexed = 0
    RulebookEntry.for_csv(csv_path).each_slice(RuleIndexer::BATCH_SIZE) do |batch|
      batch.each do |entry|
        vector = RuleIndexer.send(:embed, RuleIndexer.send(:indexable_text, entry))
        entry.update_columns(embedding: vector.pack("f*"))
        indexed += 1
      end
      update_progress(
        stage:             "indexing",
        chunks_total:      chunks_total,
        chunks_done:       chunks_total,
        articles_extracted: articles_extracted,
        entries_total:     entries_total,
        entries_indexed:   indexed
      )
    end
  end

  def import_flashcards(anki_csv_path)
    @document.flashcards.delete_all
    position = 0

    CSV.foreach(anki_csv_path, headers: true) do |row|
      full_front = row["front"].to_s.strip
      back       = row["back"].to_s.strip
      next if full_front.empty? || back.empty?

      if full_front =~ /\A(.*?)\n\n<i>(.*?)<\/i>\z/m
        front     = $1.strip
        reference = $2.strip
      else
        front     = full_front
        reference = nil
      end

      @document.flashcards.create!(
        front:     front,
        back:      back,
        reference: reference,
        position:  position
      )
      position += 1
    end
  end

  def broadcast_status
    Turbo::StreamsChannel.broadcast_replace_to(
      "document_#{@document.id}_status",
      target:  "flashcard-status",
      partial: "documents/flashcard_status",
      locals:  { document: @document }
    )
  end
end
