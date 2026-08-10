class TextChunker
  CHARS_PER_TOKEN = 4

  # content       — chunk text
  # chunk_index   — position in the sequence (0-based)
  # first_page    — first PDF page this chunk covers (1-indexed, nil if unavailable)
  # last_page     — last PDF page this chunk covers  (1-indexed, nil if unavailable)
  # byte_start    — UTF-8 byte offset in the full document text
  # byte_end      — UTF-8 byte offset end
  # page_hierarchy — Array of kreuzberg HierarchicalBlock objects for the spanned pages
  #                  each block has: .level ("h1".."h6" or "body"), .text, .font_size, .bbox
  EnrichedChunk = Data.define(
    :content,
    :chunk_index,
    :first_page,
    :last_page,
    :byte_start,
    :byte_end,
    :page_hierarchy
  )

  def initialize(chunk_size: 512, overlap: 0)
    raise ArgumentError, "chunk_size must be positive" unless chunk_size > 0
    raise ArgumentError, "overlap must be non-negative and less than chunk_size" unless overlap >= 0 && overlap < chunk_size

    @chunk_size = chunk_size
    @overlap    = overlap
  end

  # extraction: PdfToText::ExtractionResult
  # returns:    Array<EnrichedChunk>
  def chunk(extraction)
    return chunk_from_kreuzberg(extraction) if extraction.raw_chunks&.any?

    chunk_fallback(extraction.content)
  end

  private

  PAGE_MARKER = /<!--\s*PAGE\s+(\d+)\s*-->/

  # Use kreuzberg's native chunks. The native extension doesn't populate
  # first_page/last_page directly, but kreuzberg inserts <!-- PAGE N --> markers
  # into the content when insert_page_markers: true is set. Parse those to
  # derive the page range, then strip the markers from the final content.
  def chunk_from_kreuzberg(extraction)
    hierarchy_map = build_page_hierarchy_map(extraction.pages)

    extraction.raw_chunks.map do |k|
      first_page, last_page = extract_page_range(k.content)
      clean_content         = strip_page_markers(k.content)
      pages                 = first_page && last_page ? (first_page..last_page).to_a : []

      EnrichedChunk.new(
        content:        clean_content,
        chunk_index:    k.chunk_index,
        first_page:     first_page,
        last_page:      last_page,
        byte_start:     k.byte_start,
        byte_end:       k.byte_end,
        page_hierarchy: pages.flat_map { |pg| hierarchy_map[pg] || [] }
      )
    end
  end

  # Returns [first_page, last_page] integers parsed from <!-- PAGE N --> markers,
  # or [nil, nil] if no markers are present.
  def extract_page_range(content)
    page_numbers = content.scan(PAGE_MARKER).flatten.map(&:to_i)
    return [ nil, nil ] if page_numbers.empty?

    [ page_numbers.min, page_numbers.max ]
  end

  def strip_page_markers(content)
    content.gsub(PAGE_MARKER, "").gsub(/\n{3,}/, "\n\n").strip
  end

  # Fallback: word-window chunking with synthetic byte offsets (no kreuzberg chunks).
  def chunk_fallback(text)
    words       = text.split(/\s+/)
    window      = tokens_to_words(@chunk_size)
    step        = tokens_to_words(@chunk_size - @overlap)
    chunks      = []
    byte_cursor = 0
    i           = 0

    while i < words.length
      content = words[i, window].join(" ")
      chunks << EnrichedChunk.new(
        content:        content,
        chunk_index:    chunks.size,
        first_page:     nil,
        last_page:      nil,
        byte_start:     byte_cursor,
        byte_end:       byte_cursor + content.bytesize,
        page_hierarchy: []
      )
      break if i + window >= words.length
      byte_cursor += content.bytesize + 1
      i += step
    end

    chunks
  end

  # Synthetic block for pages where kreuzberg did not populate PageHierarchy.
  # Quacks like Kreuzberg::Result::HierarchicalBlock (.level, .text).
  SyntheticBlock = Struct.new(:level, :text, :font_size, :bbox)

  # Map page_number → Array<block> for O(1) lookup per chunk.
  # Prefers kreuzberg's native PageHierarchy blocks; falls back to extracting
  # short lines from the page's text content when hierarchy is nil (common for
  # PDFs whose font-size variance doesn't trigger kreuzberg's k-means clustering).
  def build_page_hierarchy_map(pages)
    return {} unless pages

    pages.each_with_object({}) do |page, map|
      next unless page.page_number

      blocks = if page.hierarchy&.blocks&.any?
        page.hierarchy.blocks
      else
        content_heading_blocks(page.content)
      end

      map[page.page_number] = blocks if blocks.any?
    end
  end

  # Extract pseudo-headings from page text: any line ≤ HEADING_MAX_CHARS
  # characters is treated as a heading-level marker (h2).  Short lines in
  # rulebook PDFs are virtually always rule titles or section headers.
  HEADING_MAX_CHARS = 70

  def content_heading_blocks(content)
    return [] if content.nil? || content.strip.empty?

    content
      .split("\n")
      .map(&:strip)
      .reject(&:empty?)
      .select { |line| line.length <= HEADING_MAX_CHARS }
      .uniq
      .map { |line| SyntheticBlock.new("h2", line, nil, nil) }
  end

  def tokens_to_words(token_count)
    [ (token_count * CHARS_PER_TOKEN / 6.0).ceil, 1 ].max
  end
end
