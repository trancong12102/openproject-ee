module Worklogs
  module Coverage
    # The coverage table as a workbook: the same rows as the CSV, with the
    # figures typed as numbers, the header frozen and the columns sized.
    class XlsxExport
      attr_reader :table

      def initialize(result:)
        @table = ExportTable.new(result:)
      end

      def to_xlsx
        Xlsx::Workbook.new do |book|
          book.sheet(I18n.t("worklogs.coverage.title")) do |sheet|
            sheet.format_columns(:hours, from: ExportTable::NUMERIC_FROM)
            sheet.format_column(table.header.size - 1, :integer)

            sheet.title(title)
            sheet.blank
            sheet.header(table.header)
            table.lines.each { |line| sheet.row(line.values) }
            sheet.total(table.total_line.values)
            sheet.blank
            table.notes.each { |note| sheet.note(note) }
          end
        end.to_xlsx
      end

      private

      def title
        "#{I18n.t('worklogs.coverage.title')} · #{table.query.period_label}"
      end
    end
  end
end
