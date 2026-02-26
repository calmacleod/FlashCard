class RuleSearchController < ApplicationController
  def index
    load_filter_data
    @results = []
  end

  def preview
    source_csv  = params[:source_csv].presence
    rule_number = params[:rule_number].presence
    section     = params[:section].presence
    article     = params[:article].presence

    query_parts = [
      rule_number.present? ? "Rule #{rule_number}" : nil,
      section.present?     ? "Section #{section}"  : nil,
      article.present?     ? "Article #{article}"  : nil
    ].compact
    query = query_parts.any? ? query_parts.join(" ") : "."

    results = RuleSearcher.search(
      query,
      source_csv:,
      rule_number:,
      section:,
      article:,
      limit: 10
    )

    render partial: "preview", locals: { entries: results }
  end

  def search
    load_filter_data
    @query      = params[:query]
    source_csv  = params[:source_csv].presence
    rule_number = params[:rule_number].presence
    section     = params[:section].presence
    article     = params[:article].presence

    if @query.present? || rule_number.present? || section.present? || article.present?
      @results = RuleSearcher.search(
        @query.presence || ".",
        source_csv:,
        rule_number:,
        section:,
        article:,
        limit: 15
      )
    else
      @results = []
    end

    render :index
  end

  private

  def load_filter_data
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv)

    @rule_numbers = RulebookEntry.where.not(rule_number: [ nil, "" ]).distinct.order(:rule_number).pluck(:rule_number)

    @rule_numbers_by_source = RulebookEntry.where.not(rule_number: [ nil, "" ])
                                           .distinct
                                           .pluck(:source_csv, :rule_number)
                                           .each_with_object({}) { |(csv, rule), h| (h[csv] ||= []) << rule }
                                           .transform_values { |v| v.sort.uniq }

    @sections_by_rule = RulebookEntry.where.not(section: [ nil, "" ])
                                     .distinct
                                     .pluck(:rule_number, :section)
                                     .each_with_object({}) { |(rule, sec), h| (h[rule] ||= []) << sec }
                                     .transform_values { |v| v.sort.uniq }

    @articles_by_section = RulebookEntry.where.not(article: [ nil, "" ])
                                        .distinct
                                        .pluck(:section, :article)
                                        .each_with_object({}) { |(sec, art), h| (h[sec] ||= []) << art }
                                        .transform_values { |v| v.sort.uniq }
  end
end
