class FlashCardPromptBuilder
  def self.build(pdf_text:, guidance:, notes:)
    <<~PROMPT
      You are an assistant that creates flash cards for Anki.
      Return ONLY valid JSON (no markdown) as an array of objects like:
      [{"front":"...","back":"..."}, ...]
      Do not include any extra keys, headers, or commentary.

      PDF_CONTENT:
      #{pdf_text}

      USER_NOTES:
      #{notes.empty? ? "No additional notes." : notes}

      USER_GUIDANCE:
      #{guidance.empty? ? "Create clear, concise study cards." : guidance}
    PROMPT
  end
end
