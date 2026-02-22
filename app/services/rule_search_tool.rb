class RuleSearchTool < RubyLLM::Tool
  description "Search the rulebook for rules, sections, and articles relevant to a query."

  params do
    string :query,       description: "Descriptive keyword phrase for the concept you are looking up (e.g. 'time count penalty', 'player substitution procedure'). Do NOT embed rule, section, or article numbers here — use the dedicated filter parameters only when you are 100% certain of the exact identifier from a prior search result."
    string :rule_number, required: false, description: "Only supply this when you have already seen this exact rule number in a previous search result and are certain it is correct. Omit it otherwise — an incorrect value will exclude relevant results."
    string :section,     required: false, description: "Only supply this when you have already seen this exact section number in a previous search result and are certain it is correct. Omit it otherwise."
    string :article,     required: false, description: "Only supply this when you have already seen this exact article number in a previous search result and are certain it is correct. Omit it otherwise."
  end

  def initialize(source_csv:)
    @source_csv = source_csv
    super()
  end

  def execute(query: nil, rule_number: nil, section: nil, article: nil)
    return "Error: a descriptive query phrase is required. Do not call this tool with only filter parameters." if query.blank?

    results = RuleSearcher.search(query, source_csv: @source_csv, rule_number: rule_number, section: section, article: article, limit: 5)
    return "No relevant rules found." if results.empty?

    results.map do |r|
      label = [ r[:rule_number], r[:section], r[:article] ].compact.reject(&:empty?).join(" › ")
      "#{label}\n#{r[:text]}"
    end.join("\n\n---\n\n")
  end
end
