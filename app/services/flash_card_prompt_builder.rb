class FlashCardPromptBuilder
  def self.build(pdf_text:, guidance:, notes:, section_title:, min_cards:, max_cards:)
    <<~PROMPT
      You are an assistant that creates study flash cards for Anki.
      These flash cards must be useful for studying.
      Accuracy is critical: DO NOT guess, infer, or add facts that are not explicitly stated.
      If the text does not support a fact, skip it.

      Front sides MUST ask a question or pose a situation.
      Avoid cards that merely ask the learner to recall exact wording, quotes, or rule numbers.
      Do not create cards like "What does Rule 1.2.3 say?" unless the front asks a concrete question about the meaning/application.

      Return ONLY valid JSON (no markdown) as an array of objects like:
      [{"front":"...","back":"..."}, ...]
      Each card must be grounded in the provided text.
      Keep answers short and factual.
      If there are no valid cards, return [].
      Create between #{min_cards} and #{max_cards} cards for this section, when possible.

      SECTION_TITLE:
      #{section_title}

      SECTION_CONTENT:
      #{pdf_text}

      USER_NOTES:
      #{notes.empty? ? "No additional notes." : notes}

      USER_GUIDANCE:
      #{guidance.empty? ? "Create clear, concise study cards." : guidance}
    PROMPT
  end
end
