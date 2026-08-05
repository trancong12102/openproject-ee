require "csv"

module Worklogs
  module Reports
    # The report as a spreadsheet reads the same as the report on screen: the
    # same rows, in the same order, with the same totals — anything else and the
    # export becomes a second, silently different report.
    #
    # Figures are written as bare numbers, not as "35h 30m": a CSV is opened to
    # be summed, and a duration string cannot be.
    class CsvExport
      attr_reader :result, :detail

      def initialize(result:, detail: false)
        @result = result
        @detail = detail
      end

      def to_csv
        detail ? detail_csv : pivot_csv
      end

      private

      def pivot_csv
        data = TableData.new(result:)

        CSV.generate do |csv|
          csv << data.header
          data.rows.each { |row| csv << (row.path + row.values) }
          csv << ([data.footer_label] + Array.new(data.depth - 1) + data.footer_values)
          data.notes.each { |note| csv << [note] }
        end
      end

      def detail_csv
        data = DetailData.new(result:)

        CSV.generate do |csv|
          csv << data.header
          data.each_row { |row| csv << row.values }
          data.notes.each { |note| csv << [note] }
        end
      end
    end
  end
end
