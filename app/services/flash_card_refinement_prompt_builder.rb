class FlashCardRefinementPromptBuilder
  def self.build(card_front:, card_back:, user_instruction:)
    <<~PROMPT
      You are reviewing a flash card for accuracy and usefulness.
      Follow the user instruction strictly. Do not add new facts.

      Decide ONE action:
      - "keep" (keep unchanged)
      - "change" (keep but rewrite)
      - "discard" (remove the card)

      Return ONLY valid JSON (no markdown):
      {"action":"keep|change|discard","front":"...","back":"...","reason":"..."}
      - If action is "keep", front/back can be empty strings.
      - If action is "change", provide the rewritten front/back.
      - If action is "discard", front/back can be empty strings.

      USER_INSTRUCTION:
      #{user_instruction}

      CARD_FRONT:
      #{card_front}

      CARD_BACK:
      #{card_back}
    PROMPT
  end
end
