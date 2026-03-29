
class PdfToText
  ExtractionResult = Data.define(:content, :raw_chunks, :pages, :document)

  # Runs a single kreuzberg extraction with:
  #   - per-page content + heading hierarchy (h1-h6 blocks with font sizes + bboxes)
  #   - full document structure tree (parent/children node graph)
  #   - native chunking so each chunk carries first_page, last_page, byte_start, byte_end
  def self.extract(pdf_path, chunk_size: 512)
    raise ArgumentError, "File not found: #{pdf_path}" unless File.exist?(pdf_path)
    raise ArgumentError, "Expected a .pdf file" unless pdf_path.end_with?(".pdf")

    config = Kreuzberg::Config::Extraction.new(
      include_document_structure: true,
      pages: Kreuzberg::Config::PageConfig.new(extract_pages: true, insert_page_markers: true),
      pdf_options: Kreuzberg::Config::PDF.new(
        hierarchy: Kreuzberg::Config::Hierarchy.new(
          enabled: true,
          k_clusters: 6,
          include_bbox: true,
          ocr_coverage_threshold: 0.8
        )
      ),
      chunking: Kreuzberg::Config::Chunking.new(
        max_chars: chunk_size * 4  # ~4 chars per token
      )
    )

    result = Kreuzberg.extract_file_sync(path: pdf_path, config: config)

    ExtractionResult.new(
      content:    result.content,
      raw_chunks: result.chunks,
      pages:      result.pages,
      document:   result.document
    )
  end
end
