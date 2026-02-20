class RuleSearchController < ApplicationController
  def index
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv)
    @results = []
  end

  def search
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv)
    source_csv = params[:source_csv].presence
    @results = RuleSearcher.search(params[:query], source_csv:, limit: 15)
    render :index
  end
end
