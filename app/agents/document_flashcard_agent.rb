class DocumentFlashcardAgent < LlmWorkflowAgent
  class ResponseSchema < RubyLLM::Schema
    array :cards do
      object do
        string :reference, description: "Precise source heading, section, page, or other citation"
        string :front, description: "A clear question"
        string :back, description: "A concise answer supported by the source"
      end
    end
  end

  inputs :persona_name, :persona_instructions, :source_label, :source_tool
  tools { [ source_tool ] }
  schema ResponseSchema

  instructions do
    <<~PROMPT
      You create study flashcards from extracted document data. You must call the source tool before responding.

      Persona: #{persona_name}
      #{persona_instructions.strip}

      Rules:
      - Use only information returned by the source tool. Never invent facts or citations.
      - Test one meaningful idea per card.
      - Make the front a direct question and the back a complete, concise answer.
      - Avoid duplicate, trivial, or opinion-based questions.
    PROMPT
  end
end
