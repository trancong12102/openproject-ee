require "csv"

module Worklogs
  module Coverage
    # The coverage table as a spreadsheet: same people, same order, same
    # figures. See `ExportTable` for the shape; this only writes it out.
    class CsvExport
      attr_reader :table

      def initialize(result:)
        @table = ExportTable.new(result:)
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
