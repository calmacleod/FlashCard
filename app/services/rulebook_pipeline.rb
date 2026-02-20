class RulebookPipeline
  SEPARATOR = "─" * 60

  def self.run(pdf_path, **opts)
    new(pdf_path, **opts).run
  end

  def initialize(pdf_path)
    @pdf_path = File.expand_path(pdf_path)
  end

  def run
    banner "RULEBOOK PIPELINE"
    puts "PDF: #{@pdf_path}\n\n"

    step_process
    step_assemble
    step_normalize
  end

  private

  # ── Step 1: Process PDF into chunks ────────────────────────────────────────

  def step_process
    banner "STEP 1 — PROCESS PDF INTO CHUNKS"

    model = prompt_with_default("Processor model", "gemini-3-flash-preview")
    delay = prompt_with_default("Delay between chunks (seconds)", "0").to_f

    puts
    RulebookProcessor.process(@pdf_path, model: model, delay: delay)
    # RulebookProcessor handles its own confirm-or-abort prompt internally.
    # If the user aborted, chunks will be empty — abort the pipeline too.
    unless RulebookChunk.for_pdf(@pdf_path).completed.any?
      puts "\nNo completed chunks — pipeline aborted."
    end
  end

  # ── Step 2: Assemble chunks into CSV ───────────────────────────────────────

  def step_assemble
    banner "STEP 2 — ASSEMBLE CHUNKS INTO CSV"

    chunk_from = prompt_optional_int("Start from chunk index (blank = all)")
    chunk_to   = prompt_optional_int("End at chunk index   (blank = all)")
    show       = prompt_yes_no("Show chunk boundaries in output?", default: false)

    puts
    RulebookAssembler.assemble(
      @pdf_path,
      format:      :csv,
      show_chunks: show,
      chunk_from:  chunk_from,
      chunk_to:    chunk_to
    )

    @csv_path = Rails.root.join("#{File.basename(@pdf_path, File.extname(@pdf_path))}.csv").to_s
  end

  # ── Step 3: Normalize CSV into RulebookEntry records ───────────────────────

  def step_normalize
    banner "STEP 3 — NORMALIZE INTO RULEBOOK ENTRIES"

    puts "CSV: #{@csv_path}\n\n"

    direct = prompt_yes_no("Skip LLM and carry forward context directly?", default: false)

    if direct
      model = nil
      delay = 0.0
    else
      model = prompt_with_default("Normalizer model", "gemini-2.5-flash")
      delay = prompt_with_default("Delay between groups (seconds)", "0").to_f
    end

    puts
    RulebookNormalizer.normalize(
      @csv_path,
      model:    model || "gemini-2.5-flash",
      delay:    delay,
      pdf_path: @pdf_path,
      direct:   direct
    )
  end

  # ── Prompt helpers ──────────────────────────────────────────────────────────

  def banner(title)
    puts
    puts SEPARATOR
    puts title
    puts SEPARATOR
  end

  def prompt_with_default(label, default)
    print "#{label} [#{default}]: "
    $stdout.flush
    input = $stdin.gets&.strip
    input.nil? || input.empty? ? default : input
  end

  def prompt_optional_int(label)
    print "#{label}: "
    $stdout.flush
    input = $stdin.gets&.strip
    return nil if input.nil? || input.empty?
    Integer(input)
  rescue ArgumentError
    puts "  (invalid — using none)"
    nil
  end

  def prompt_yes_no(label, default:)
    flag   = default ? "Y/n" : "y/N"
    print "#{label} [#{flag}]: "
    $stdout.flush
    input = $stdin.gets&.strip&.downcase
    return default if input.nil? || input.empty?
    input == "y"
  end
end
