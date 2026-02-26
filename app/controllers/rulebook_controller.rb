class RulebookController < ApplicationController
  def index
    @source_csvs = RulebookEntry.distinct.pluck(:source_csv).sort
  end

  def show
    source_csv = params[:source_csv]
    entries = RulebookEntry.for_csv(source_csv)
    @source_csv = source_csv
    @grouped = entries.group_by(&:rule_number)
                      .transform_values { |re|
                        re.group_by(&:section)
                          .transform_values { |se| se.group_by(&:article) }
                      }
  end
end
