module Worklogs
  # Who logged their hours and who did not — the question a report cannot
  # answer, because a report starts from the time entries and the people worth
  # chasing are the ones with none.
  class CoverageController < ApplicationController
    include Worklogs::TimesheetHelper
    include Worklogs::CoverageHelper

    before_action :require_login
    authorize_with_global_permission :view_worklogs_coverage

    before_action :load_query

    menu_item :worklogs_coverage

    layout "global"

    def index
      @result = Coverage::Result.new(query: @query, viewer: current_user)

      respond_to do |format|
        format.html
        format.csv do
          send_data(Coverage::CsvExport.new(result: @result).to_csv,
                    type: "text/csv; charset=utf-8",
                    filename: "#{export_filename}.csv",
                    disposition: "attachment")
        end
        format.xlsx do
          send_data(Coverage::XlsxExport.new(result: @result).to_xlsx,
                    type: Xlsx::Workbook::CONTENT_TYPE,
                    filename: "#{export_filename}.xlsx",
                    disposition: "attachment")
        end
      end
    end

    private

    def load_query
      @query = Coverage::Query.from_params(params)
    end

    def export_filename
      "worklogs-coverage-#{@query.from.iso8601}-#{@query.to.iso8601}"
    end
  end
end
