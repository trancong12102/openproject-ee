module Worklogs
  module Reports
    # The report as a workbook.
    #
    # Built on core's own `OpenProject::XlsExport::SpreadsheetBuilder`, so the
    # file opens exactly like the work package and cost exports people here
    # already receive — same column sizing, same conventions, and nothing new
    # to install: `spreadsheet` is already in the image's frozen bundle.
    #
    # Figures are written as numbers with a cell format, never as text. An
    # export whose totals cannot be re-summed is a screenshot with extra steps.
    class XlsExport
      include ActionView::Helpers::NumberHelper
      include Worklogs::ReportsHelper
      include ExportMetadata

      attr_reader :result, :detail, :title

      def initialize(result:, detail: false, title: nil)
        @result = result
        @detail = detail
        @title = title.presence || I18n.t("worklogs.reports.title")
      end

      def to_xls
        builder = OpenProject::XlsExport::SpreadsheetBuilder.new(I18n.t("worklogs.reports.title"))

        write_pivot(builder)
        write_detail(builder) if detail

        builder.xls
      end

      private

      def query = result.query

      def write_pivot(builder)
        data = TableData.new(result:)

        builder.add_title(title)
        meta_rows.each { |row| builder.add_row(row) }
        builder.add_empty_row

        builder.add_headers(data.header)
        format_value_columns(builder, data.depth, data.header.size)

        data.rows.each { |row| builder.add_row(row.path + row.values) }
        builder.add_sums([data.footer_label] + Array.new(data.depth - 1) + data.footer_values)

        data.notes.each { |note| builder.add_row([note]) }
      end

      def write_detail(builder)
        data = DetailData.new(result:)

        builder.worksheet(1, I18n.t("worklogs.reports.detail.sheet"))
        builder.add_title(I18n.t("worklogs.reports.detail.sheet"))
        meta_rows(grouping: false).each { |row| builder.add_row(row) }
        builder.add_empty_row

        builder.add_headers(data.header)
        format_detail_columns(builder, data)

        data.each_row { |row| builder.add_row(row.values) }
        data.notes.each { |note| builder.add_row([note]) }
      end

      def format_value_columns(builder, first_index, last_index)
        (first_index...last_index).each do |index|
          builder.add_format_option_to_column(index, number_format: measure_number_format)
        end
      end

      def format_detail_columns(builder, data)
        hours_index = data.header.size - (data.costs_visible? ? 3 : 2)
        builder.add_format_option_to_column(hours_index, number_format: "0.00")
        builder.add_format_option_to_column(hours_index + 1, number_format: currency_number_format) if data.costs_visible?
      end

      def measure_number_format
        case measure_format
        when :integer then "0"
        when :currency then currency_number_format
        else "0.00"
        end
      end

      # The instance's own currency sign, so the workbook reads the way the
      # screen did rather than in whatever locale Excel happens to open in.
      def currency_number_format
        sign = Setting.costs_currency.to_s.delete('"')
        pattern = Setting.costs_currency_format.to_s.presence || "%n %u"

        pattern.gsub("%n", "#,##0.00").gsub("%u", %("#{sign}"))
      rescue StandardError
        "#,##0.00"
      end
    end
  end
end
