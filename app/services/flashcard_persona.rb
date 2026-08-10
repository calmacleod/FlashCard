class FlashcardPersona
  Persona = Data.define(:key, :name, :description, :instructions) do
    def option_label = "#{name} — #{description}"
  end

  PERSONAS = [
    Persona.new(
      key: "generalist",
      name: "Generalist",
      description: "Balanced questions for understanding and recall",
      instructions: <<~TEXT
        Create broadly useful cards covering the document's main facts, concepts, definitions, and relationships.
        Prefer clear questions with concise answers. Avoid trivia and duplicate questions.
      TEXT
    ),
    Persona.new(
      key: "football_rules",
      name: "Football rules",
      description: "Rules, exceptions, measurements, and penalties",
      instructions: <<~TEXT
        Create cards as an expert football rules educator. Prioritize requirements, limits, measurements,
        timing, definitions, exceptions, enforcement, and penalties. Use precise rule/section/article citations
        when the source provides them. Aim for 1-3 cards per meaningful article, with fewer for sparse text.
      TEXT
    ),
    Persona.new(
      key: "exam_prep",
      name: "Exam prep",
      description: "Specific questions that expose common mistakes",
      instructions: <<~TEXT
        Create assessment-style cards that test exact distinctions, likely misconceptions, sequences, and
        conditions. Questions should have one defensible answer and should not rely on vague wording.
      TEXT
    ),
    Persona.new(
      key: "practical_application",
      name: "Practical application",
      description: "Scenario-based questions about applying the material",
      instructions: <<~TEXT
        Create short scenario-based cards that ask what someone should do, decide, or expect in practice.
        Keep every scenario directly grounded in the extracted source and include the governing reference.
      TEXT
    )
  ].index_by(&:key).freeze

  def self.all = PERSONAS.values

  def self.find!(key)
    PERSONAS.fetch(key.to_s) { raise ArgumentError, "Unknown flashcard persona" }
  end
end
