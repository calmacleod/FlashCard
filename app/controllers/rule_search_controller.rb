class RuleSearchController < ApplicationController
  def index
    load_filter_data
    @results = []
  end

  def search
    load_filter_data
    @query = params[:query]
    source_csv = params[:source_csv].presence
    rule_number = params[:rule_number].presence

    if @query.present?
      @results = RuleSearcher.search(@query, source_csv:, rule_number:, limit: 15)
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
  end
end
