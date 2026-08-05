require "csv"

module Worklogs
  module Reports
    # The report as a spreadsheet reads the same as the report on screen: the
    # same rows, in the same order, with the same totals — anything else and the
    # export becomes a second, silently different report.
    #
    # CSV only, on purpose: the runtime image ships a frozen bundle, so adding a
    # spreadsheet gem is not possible. Every spreadsheet program opens this.
    class CsvExport
      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def to_csv
        CSV.generate(force_quotes: false) do |csv|
          csv << header
          each_row { |row| csv << row }
          csv << footer
        end
      end

      private

      def query
        result.query
      end

      def measure
        query.measure
      end

      def header
        columns = query.row_dimensions.map(&:label)
        columns.concat(result.columns.map { |column| column.label.text }) if result.columns?
        columns << I18n.t("worklogs.reports.total")
        columns
      end

      # Every level is written on every line rather than left blank under its
      # parent: a spreadsheet gets sorted and filtered, and indentation does not
      # survive either.
      def each_row(nodes = result.nodes, prefix = [], &)
        nodes.each do |node|
          path = prefix + [node.label.text]

          if node.leaf?
            yield(pad(path) + values_for(node))
          else
            yield(pad(path) + values_for(node))
            each_row(node.children, path, &)
          end
        end
      end

      def footer
        pad([I18n.t("worklogs.reports.total")]) + values_for_measures(result.column_totals, result.totals)
      end

      def pad(path)
        path + Array.new(query.row_dimensions.size - path.size, nil)
      end

      def values_for(node)
        values_for_measures(node.values, node.measures)
      end

      def values_for_measures(by_column, totals)
        values = []
        values.concat(result.columns.map { |column| number(by_column[column.key]) }) if result.columns?
        values << number(totals)
        values
      end

      def number(measures)
        return 0 if measures.nil?

        value = measures[measure.to_sym]
        measure == "entries" ? value.to_i : value.to_f.round(2)
      end
    end
  end
end
