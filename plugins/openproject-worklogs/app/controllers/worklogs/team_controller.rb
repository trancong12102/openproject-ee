module Worklogs
  # The whole team's week or month, one line per person.
  #
  # Behind the same permission as coverage: both are the manager's act of
  # looking at everybody, and neither shows an hour that `TimeEntry.visible`
  # would not have shown the same viewer in core.
  class TeamController < ApplicationController
    include Worklogs::TimesheetHelper
    include Worklogs::TeamHelper

    before_action :require_login
    authorize_with_global_permission :view_worklogs_coverage

    before_action :load_query

    menu_item :worklogs_team

    layout "global"

    def index
      @sheet = Team::Sheet.new(query: @query, viewer: current_user)

      respond_to do |format|
        format.html
        format.csv do
          send_data(Team::CsvExport.new(sheet: @sheet).to_csv,
                    type: "text/csv; charset=utf-8",
                    filename: "#{export_filename}.csv",
                    disposition: "attachment")
        end
        format.xlsx do
          send_data(Team::XlsxExport.new(sheet: @sheet).to_xlsx,
                    type: Xlsx::Workbook::CONTENT_TYPE,
                    filename: "#{export_filename}.xlsx",
                    disposition: "attachment")
        end
      end
    end

    private

    def load_query
      @query = Team::Query.from_params(params)
    end

    def export_filename
      "worklogs-team-#{@query.span.start_date.iso8601}-#{@query.span.end_date.iso8601}"
    end
  end
end
