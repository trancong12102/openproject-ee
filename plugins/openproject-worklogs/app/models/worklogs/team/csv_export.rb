require "csv"

module Worklogs
  module Team
    # The team sheet as a spreadsheet: same people, same order, same figures,
    # one column per day.
    #
    # Numbers are written as numbers — a spreadsheet is opened to be re-summed,
    # and "7h 30m" cannot be. Expanded rows come along under their person, so
    # the file says as much as the screen it was taken from.
    class CsvExport
      attr_reader :table

      def initialize(sheet:)
        @table = ExportTable.new(sheet:)
      end

      def to_csv
        CSV.generate do |csv|
          csv << table.header
          table.lines.each { |line| csv << line.values }
          csv << table.total_line.values
          table.notes.each { |note| csv << [note] }
        end
      end
    end
  end
end
