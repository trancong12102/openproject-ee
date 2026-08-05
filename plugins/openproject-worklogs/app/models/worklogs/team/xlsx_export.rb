module Worklogs
  module Team
    # The team sheet as a workbook: the same rows as the CSV, with the figures
    # typed as numbers, the header frozen and the columns sized.
    class XlsxExport
      attr_reader :table

      def initialize(sheet:)
        @table = ExportTable.new(sheet:)
      end

      def to_xlsx
        Xlsx::Workbook.new do |book|
          book.sheet(I18n.t("worklogs.team.title")) do |sheet|
            sheet.format_columns(:hours, from: ExportTable::NUMERIC_FROM)
            # Utilisation is the last column and is a count of percent, not
            # hours; it is the one figure here nobody should re-sum.
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

      # What was asked, next to the answer. A workbook outlives the tab it came
      # from, and six weeks later "41h 30m of what?" has no answer at all
      # unless the file carries the question.
      def title
        "#{I18n.t('worklogs.team.title')} · #{table.dates.first.iso8601} – #{table.dates.last.iso8601}"
      end
    end
  end
end
