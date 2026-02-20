class RuleSearchController < ApplicationController
  def index
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv)
    @results = []
  end

  def search
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv)
    @query = params[:query]
    source_csv = params[:source_csv].presence

    if @query.present?
      @results = RuleSearcher.search(@query, source_csv:, limit: 15)
    else
      @results = []
    end

    render :index
  end
end
