class RuleSearchTool < RubyLLM::Tool
  description "Search the rulebook for rules, sections, and articles relevant to a query."

  params do
    string :query, description: "The question or situation to look up in the rulebook"
    string :rule_number, required: false, description: "Optional rule number to narrow the search, e.g. 'Rule 3'"
  end

  def initialize(source_csv:)
    @source_csv = source_csv
    super()
  end

  def execute(query:, rule_number: nil)
    results = RuleSearcher.search(query, source_csv: @source_csv, rule_number: rule_number, limit: 5)
    return "No relevant rules found." if results.empty?

    results.map do |r|
      label = [ r[:rule_number], r[:section], r[:article] ].compact.reject(&:empty?).join(" › ")
      "#{label}\n#{r[:text]}"
    end.join("\n\n---\n\n")
  end
end
