module Worklogs
  module Reports
    # The pivot flattened into a plain table: one header, one row per node in
    # the order the screen shows them, one footer of totals.
    #
    # Every export format renders this same shape. Three formats each walking
    # the node tree themselves is three chances to produce a subtly different
    # report from the one on screen.
    class TableData
      Row = Struct.new(:path, :values, :level, :leaf, keyword_init: true) do
        def label
          path.compact.last
        end
      end

      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def query = result.query
      def measure = query.measure
      def depth = query.row_dimensions.size

      def dimension_headers
        query.row_dimensions.map(&:label)
      end

      def value_headers
        headers = result.columns? ? result.columns.map { |column| column.label.text } : []
        headers << I18n.t("worklogs.reports.total")
      end

      def header
        dimension_headers + value_headers
      end

      def rows
        @rows ||= flatten(result.nodes, [])
      end

      def footer_label
        I18n.t("worklogs.reports.total")
      end

      def footer_values
        values_for(result.column_totals, result.totals)
      end

      # What the reader should be told was left out. Silence here would read as
      # "this is everything", which is the one thing an export must never imply.
      def notes
        [].tap do |notes|
          notes << I18n.t("worklogs.reports.truncated_rows", count: result.truncated_rows) if result.truncated_rows.positive?
          if result.truncated_columns.positive?
            notes << I18n.t("worklogs.reports.truncated_columns", count: result.truncated_columns)
          end
        end
      end

      private

      # Every level is written on every line rather than left blank under its
      # parent: a spreadsheet gets sorted and filtered, and neither indentation
      # nor an implied parent survives that.
      def flatten(nodes, prefix)
        nodes.flat_map do |node|
          path = prefix + [node.label.text]
          row = Row.new(path: pad(path), values: values_for(node.values, node.measures),
                        level: path.size - 1, leaf: node.leaf?)

          [row, *flatten(node.children, path)]
        end
      end

      def pad(path)
        path + Array.new(depth - path.size, nil)
      end

      def values_for(by_column, totals)
        values = []
        values.concat(result.columns.map { |column| number(by_column[column.key]) }) if result.columns?
        values << number(totals)
        values
      end

      def number(measures)
        return measure == "entries" ? 0 : 0.0 if measures.nil?

        value = measures[measure.to_sym]
        measure == "entries" ? value.to_i : value.to_f.round(2)
      end
    end
  end
end
