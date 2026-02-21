class RuleReferenceLinkTool < RubyLLM::Tool
  description "Generate a hyperlink to the rule search page with preset filters for a specific rule, section, " \
              "and/or article. Call this once for each distinct rule reference you cite in your answer, " \
              "then include all returned links in a '### References' section at the very end of your response."

  params do
    string :label,       description: "Human-readable label for the link, e.g. 'Rule 4 › Section 2 › Article 3'"
    string :rule_number, required: false, description: "The rule number to pre-fill, e.g. 'Rule 4' or '4'"
    string :section,     required: false, description: "The section number to include, e.g. '2'"
    string :article,     required: false, description: "The article number to include, e.g. '3'"
  end

  BASE_PATH = "/rule_search/search"

  def initialize(source_csv:, base_url: nil)
    @source_csv = source_csv
    @base_url   = base_url.to_s.chomp("/")
    super()
  end

  def execute(label:, rule_number: nil, section: nil, article: nil)
    params = {}
    params[:source_csv]  = @source_csv  if @source_csv.present?
    params[:rule_number] = rule_number  if rule_number.present?
    params[:section]     = section      if section.present?
    params[:article]     = article      if article.present?

    url = "#{@base_url}#{BASE_PATH}?#{params.to_query}"
    "[#{label}](#{url})"
  end
end
