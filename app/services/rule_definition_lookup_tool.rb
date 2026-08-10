class RuleDefinitionLookupTool < RubyLLM::Tool
  description "Look up the exact text of a rule by its Rule Number, Section Number, and/or Article Number. " \
              "Use this when you know (or the user has cited) specific identifiers rather than a keyword query."

  param :rule_number, desc: "The rule number only, e.g. '4' or 'Rule 4'. Do NOT include the section or article here."
  param :section,     desc: "The section number only, e.g. '2' or 'Section 2'. Do NOT use dotted notation like '4.2' — pass each part separately.", required: false
  param :article,     desc: "The article number only, e.g. '4' or 'Article 4'. Do NOT prefix with the rule or section number.", required: false

  def initialize(source_csv:)
    @source_csv = source_csv
    super()
  end

  def execute(rule_number: nil, section: nil, article: nil)
    if [ rule_number, section, article ].all?(&:blank?)
      return "Please supply at least one of: rule_number, section, or article."
    end

    scope = RulebookEntry.where(source_csv: @source_csv)
    scope = apply_filter(scope, :rule_number, rule_number)
    scope = apply_filter(scope, :section,     section)
    scope = apply_filter(scope, :article,     article)

    entries = scope.order(:entry_index).limit(20)
    return "No entries found for the given identifiers." if entries.empty?

    entries.map do |e|
      label = [ e.rule_number, e.section, e.article ].compact.reject(&:empty?).join(" › ")
      "#{label}\n#{e.text}"
    end.join("\n\n---\n\n")
  end

  private

  # Match flexibly so "3" finds "Rule 3", "rule 3", etc. and vice versa.
  # Builds a short list of candidate strings and uses an IN check first,
  # then falls back to LIKE anchored with the digit-only variant to avoid
  # over-matching (e.g. "3" must not match "13" or "23").
  def apply_filter(scope, column, value)
    return scope if value.blank?

    normalized = value.to_s.strip
    digit_only = normalized.gsub(/\A[a-z\s]+/i, "").strip

    # Exact candidates: what the user supplied + stripped digit form
    exact_candidates = [ normalized, digit_only ].uniq.reject(&:blank?)

    result = scope.where(column => exact_candidates)
    return result unless result.empty?

    # Fallback: column contains the digit-only part as a whole word/token.
    # Use the longer normalized form for LIKE to stay precise.
    like_value = exact_candidates.max_by(&:length)
    scope.where(scope.klass.arel_table[column].matches("%#{like_value}%"))
  end
end
