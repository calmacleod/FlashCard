
class ChunkCategorizer
  DEFAULT_MODEL    = "gpt-5.4-nano"
  CATEGORY_PATTERN = /\A[a-z0-9_]+(\.([a-z0-9_]+))*\z/

  SYSTEM_INSTRUCTIONS = <<~INSTRUCTIONS.strip
    You are a document structure analyzer. Assign a hierarchical dotted category to a chunk of document text.

    Rules:
    - Use snake_case for each segment (e.g. player_conduct, not playerConduct)
    - Separate depth levels with periods: chapter.section.subsection
    - When PDF heading structure is provided, use it as the authoritative hierarchy seed
    - Be consistent with the previously established category path
    - If the chunk falls under a heading already seen, extend that path rather than restarting
    - If you cannot determine a deeper level, reuse the previous category as-is
    - When neighbor heading context is provided, use the surrounding headings to infer
      which section this chunk belongs to based on its position between them
  INSTRUCTIONS

  # category — dotted hierarchy string e.g. "rules.player_conduct.fouls"
  # chunk    — TextChunker::EnrichedChunk (carries first_page, last_page,
  #            byte_start, byte_end, chunk_index for downstream linking)
  Result = Data.define(:category, :chunk)

  class CategorySchema < RubyLLM::Schema
    string :category,
      description: "Dotted hierarchical category in snake_case, e.g. rules.player_conduct.fouls.technical_foul"
  end

  def initialize(model: DEFAULT_MODEL)
    @model = model
  end

  # chunks:  Array<TextChunker::EnrichedChunk>
  # returns: Array<Result>
  def categorize(chunks)
    previous_category = nil
    previous_chunk    = nil

    chunks.each_with_index.map do |chunk, idx|
      category          = determine_category(chunk, previous_category, previous_chunk, chunks, idx)
      previous_category = category
      previous_chunk    = chunk
      Result.new(category: category, chunk: chunk)
    end
  end

  private

  def determine_category(chunk, previous_category, previous_chunk, all_chunks, chunk_idx)
    user_prompt = build_user_prompt(chunk, previous_category, previous_chunk, all_chunks, chunk_idx)

    response = RubyLLM.chat(model: @model)
                      .with_instructions(SYSTEM_INSTRUCTIONS)
                      .with_thinking(budget: 0)
                      .with_schema(CategorySchema)
                      .ask(user_prompt)

    raw      = response.content.is_a?(Hash) ? response.content : JSON.parse(response.content)
    category = raw.fetch("category", "").to_s.strip.downcase.gsub(/\s+/, "_")

    valid_category?(category) ? category : fallback(previous_category)
  rescue => e
    Rails.logger.warn("ChunkCategorizer: failed for chunk #{chunk.chunk_index} (#{e.message}), using fallback")
    fallback(previous_category)
  end

  # Builds the user message only — system instructions are set separately via
  # with_instructions so the chunk content is not buried inside a combined blob.
  def build_user_prompt(chunk, previous_category, previous_chunk, all_chunks, chunk_idx)
    lines = []

    headings = extract_headings(chunk.page_hierarchy)

    if headings.any?
      page_label = page_label_for(chunk)
      lines << "--- PDF HEADING STRUCTURE (#{page_label}) ---"
      lines << headings.map { |h| "#{h[:level].upcase}: #{h[:text]}" }.join("\n")
      lines << "--- END HEADING STRUCTURE ---"
      lines << ""
    else
      # No headings on this chunk — search neighbors for page/heading context.
      before_ctx, after_ctx = resolve_neighbor_headings(all_chunks, chunk_idx)

      if before_ctx || after_ctx
        lines << "--- NEIGHBOR HEADING CONTEXT (this chunk has no direct heading) ---"

        if before_ctx
          lines << "Nearest heading BEFORE (chunk #{before_ctx[:chunk_index]}, #{page_label_for(before_ctx[:chunk])}):"
          lines << before_ctx[:headings].map { |h| "#{h[:level].upcase}: #{h[:text]}" }.join("\n")
        end

        if after_ctx
          lines << "Nearest heading AFTER (chunk #{after_ctx[:chunk_index]}, #{page_label_for(after_ctx[:chunk])}):"
          lines << after_ctx[:headings].map { |h| "#{h[:level].upcase}: #{h[:text]}" }.join("\n")
        end

        lines << "--- END NEIGHBOR HEADING CONTEXT ---"
        lines << ""
      end
    end

    if previous_category && previous_chunk
      lines << "--- PREVIOUS CONTEXT ---"
      lines << "Category: #{previous_category}"
      lines << "Previous chunk:\n#{previous_chunk.content}"
      lines << "--- END PREVIOUS CONTEXT ---"
      lines << ""
    end

    page_note = chunk.first_page ? " (page #{chunk.first_page})" : ""
    lines << "Categorize this chunk#{page_note}:"
    lines << chunk.content

    lines.join("\n")
  end

  # Walk backwards then forwards from chunk_idx to find the nearest chunks
  # that carry heading hierarchy. Returns [before_ctx, after_ctx] where each
  # is nil or { chunk:, chunk_index:, headings: }.
  def resolve_neighbor_headings(chunks, idx)
    before_ctx = nil
    (idx - 1).downto(0) do |i|
      headings = extract_headings(chunks[i].page_hierarchy)
      if headings.any?
        before_ctx = { chunk: chunks[i], chunk_index: i, headings: headings }
        break
      end
    end

    after_ctx = nil
    (idx + 1).upto(chunks.length - 1) do |i|
      headings = extract_headings(chunks[i].page_hierarchy)
      if headings.any?
        after_ctx = { chunk: chunks[i], chunk_index: i, headings: headings }
        break
      end
    end

    [ before_ctx, after_ctx ]
  end

  # Filter kreuzberg HierarchicalBlock objects to headings only (h1-h6),
  # deduplicated, in document order.
  def extract_headings(page_hierarchy)
    return [] if page_hierarchy.nil? || page_hierarchy.empty?

    page_hierarchy
      .select { |block| block.level.to_s.match?(/\Ah[1-6]\z/) }
      .map    { |block| { level: block.level.to_s, text: block.text.to_s.strip } }
      .reject { |h| h[:text].empty? }
      .uniq
  end

  def page_label_for(chunk)
    return "unknown page" unless chunk.first_page

    chunk.first_page == chunk.last_page ? "page #{chunk.first_page}" : "pages #{chunk.first_page}-#{chunk.last_page}"
  end

  def valid_category?(category)
    category.match?(CATEGORY_PATTERN)
  end

  def fallback(previous_category)
    previous_category || "uncategorized"
  end
end
