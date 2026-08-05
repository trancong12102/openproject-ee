module Worklogs
  module Reports
    # The pivot itself. Rows nest up to two levels, columns are optional, and
    # every figure is a link to the entries behind it — a number nobody can
    # open is a number nobody can check.
    class TableComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::ReportsHelper

      options :query, :result

      def dates_label
        query.row_dimensions.map(&:label).join(" › ")
      end

      def columns
        result.columns
      end

      def columns?
        result.columns?
      end

      def column_span
        columns.size + 2
      end

      def cell(node, column)
        node.values.dig(column.key, query.measure.to_sym)
      end

      def formatted(value)
        worklogs_measure_cell(value, query.measure)
      end

      def formatted_total(value)
        worklogs_measure(value, query.measure)
      end

      def column_total(column)
        result.column_totals.dig(column.key, query.measure.to_sym) || 0
      end

      # Share of the biggest cell in the row, used to shade the pivot so a wide
      # table can be read at a glance instead of column by column.
      def heat(node, column)
        maximum = row_maximum(node)
        return 0 if maximum.zero?

        worklogs_share(cell(node, column), maximum)
      end

      def heat_step(node, column)
        share = heat(node, column)
        return nil if share.zero?

        [(share / 20).ceil, 1].max
      end

      def drill_down_path(node, column = nil)
        pairs = node.path.dup
        pairs << [query.column_dimension, column.key] if column && query.column_dimension

        entries_worklogs_reports_path(
          query.to_params.merge(pk: pairs.map { |dimension, _| dimension.key },
                                pv: pairs.map { |_, value| value })
        )
      end

      def drill_down_label(node, column = nil)
        parts = [node.label.text]
        parts << column.label.text if column

        I18n.t("worklogs.reports.open_entries", subject: parts.join(" · "))
      end

      def row_classes(node, level)
        classes = ["worklogs-pivot--row", "-level-#{level}"]
        classes << "-parent" unless node.leaf?
        classes
      end

      private

      def row_maximum(node)
        @row_maxima ||= {}
        @row_maxima[node.object_id] ||= columns.map { |column| cell(node, column).to_f }.max || 0
      end
    end
  end
end
