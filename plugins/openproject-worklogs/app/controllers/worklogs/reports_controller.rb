module Worklogs
  # The pivot report: any slice of the time entries a person may see, grouped
  # up to two levels deep with an optional time axis across the top.
  #
  # There is no report state on the server. A report is its URL, so every
  # control is a link, the back button works, and sharing one is copy-paste.
  class ReportsController < ApplicationController
    include OpTurbo::ComponentStream
    include Worklogs::TimesheetHelper
    include Worklogs::ReportsHelper

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_query

    menu_item :worklogs_reports

    layout "global"

    def index
      @result = Reports::Result.new(query: @query, viewer: current_user)
      @saved_reports = SavedReport.visible(current_user).includes(:user).ordered.to_a
      @saved_report = @saved_reports.find { |report| report.id == @query.report_id }

      respond_to do |format|
        format.html
        format.csv { send_data(Reports::CsvExport.new(result: @result, detail:).to_csv, **export_options("csv", "text/csv; charset=utf-8")) }
        format.xls do
          send_data(Reports::XlsExport.new(result: @result, detail:, title: export_title).to_xls,
                    **export_options("xls", "application/vnd.ms-excel"))
        end
        format.xlsx do
          send_data(Reports::XlsxExport.new(result: @result, detail:, title: export_title).to_xlsx,
                    **export_options("xlsx", Xlsx::Workbook::CONTENT_TYPE))
        end
        format.pdf do
          send_data(Reports::PDFExport.new(result: @result, title: export_title).to_pdf,
                    **export_options("pdf", "application/pdf"))
        end
      end
    end

    # The list behind a number. Without it a pivot is a set of assertions the
    # reader has to take on trust.
    def entries
      @entries = drill_down_scope.includes(:user, :activity, :project, entity: %i[type status])
                                 .order(spent_on: :desc, id: :desc)
                                 .limit(Reports::EntriesDialogComponent::LIMIT + 1)
                                 .to_a
      @entry_count = drill_down_scope.count

      respond_with_dialog(
        Reports::EntriesDialogComponent.new(entries: @entries, count: @entry_count,
                                            title: drill_down_title, query: @query,
                                            costs_visible: costs_visible?)
      )
    end

    private

    def load_query
      @query = Reports::Query.from_params(params)
    end

    def report_scope
      @report_scope ||= Reports::Scope.new(query: @query, viewer: current_user)
    end

    def costs_visible?
      report_scope.costs_visible?
    end

    def drill_down_scope
      @drill_down_scope ||= report_scope.where_dimensions(drill_down_pairs)
    end

    # `pk[]` / `pv[]` are parallel arrays so the order of the path survives the
    # round trip; the dimension keys are validated against the whitelist, and
    # the values only ever reach SQL as bound parameters.
    def drill_down_pairs
      keys = Array(params[:pk])
      values = Array(params[:pv])

      keys.each_with_index.filter_map do |key, index|
        dimension = Reports::Dimension.find(key)
        [dimension, values[index]] if dimension
      end
    end

    def drill_down_title
      parts = drill_down_pairs.map do |dimension, value|
        label = dimension.resolve([value.to_s])[value.to_s]
        label&.text.presence || I18n.t("worklogs.reports.none")
      end

      parts.any? ? parts.join(" · ") : @query.period_label
    end

    # One row per time entry rather than one row per group. The pivot answers
    # "how much"; this answers "which entries", which is what anybody billing
    # or reconciling a month has to hand to somebody else.
    def detail
      ActiveModel::Type::Boolean.new.cast(params[:detail]).present?
    end

    def export_title
      @saved_report&.name.presence || I18n.t("worklogs.reports.title")
    end

    def export_options(extension, type)
      {
        type:,
        filename: "#{export_filename}.#{extension}",
        disposition: "attachment"
      }
    end

    # Named after what it contains, not after when it was downloaded: three of
    # these in a downloads folder should be tellable apart.
    def export_filename
      slug = export_title.parameterize.presence || "worklogs"

      "#{slug}-#{@query.from.iso8601}-#{@query.to.iso8601}"
    end
  end
end
