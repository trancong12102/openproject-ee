module Worklogs
  module Reports
    # The report as an .xlsx workbook — the pivot on one sheet, and the entries
    # behind it on a second when the export asked for them.
    #
    # Same `TableData` / `DetailData` the screen, the CSV, the PDF and the old
    # .xls are all rendered from: five formats walking the node tree themselves
    # would be five chances to disagree with each other.
    class XlsxExport
      include ExportMetadata

      attr_reader :result, :detail, :title

      def initialize(result:, detail: false, title: nil)
        @result = result
        @detail = detail
        @title = title.presence || I18n.t("worklogs.reports.title")
      end

      def to_xlsx
        Xlsx::Workbook.new do |book|
          write_pivot(book)
          write_detail(book) if detail
        end.to_xlsx
      end

      private

      def query = result.query

      def write_pivot(book)
        data = TableData.new(result:)

        book.sheet(I18n.t("worklogs.reports.title")) do |sheet|
          # The first columns are the group labels; everything from there on is
          # a measure, in whichever unit the report was asked for.
          sheet.format_columns(measure_format, from: data.depth)

          sheet.title(title)
          meta_rows.each { |row| sheet.row(row) }
          sheet.blank

          sheet.header(data.header)
          data.rows.each { |row| sheet.row(row.path + row.values) }
          sheet.total([data.footer_label] + Array.new(data.depth - 1) + data.footer_values)

          next if data.notes.empty?

          sheet.blank
          data.notes.each { |note| sheet.note(note) }
        end
      end

      def write_detail(book)
        data = DetailData.new(result:)
        hours_index = data.header.size - (data.costs_visible? ? 3 : 2)

        book.sheet(I18n.t("worklogs.reports.detail.sheet")) do |sheet|
          sheet.format_column(hours_index, :hours)
          sheet.format_column(hours_index + 1, :currency) if data.costs_visible?

          sheet.title(I18n.t("worklogs.reports.detail.sheet"))
          meta_rows(grouping: false).each { |row| sheet.row(row) }
          sheet.blank

          sheet.header(data.header)
          data.each_row { |row| sheet.row(row.values) }

          next if data.notes.empty?

          sheet.blank
          data.notes.each { |note| sheet.note(note) }
        end
      end
    end
  end
end
