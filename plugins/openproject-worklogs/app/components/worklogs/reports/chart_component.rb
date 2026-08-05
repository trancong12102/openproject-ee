module Worklogs
  module Reports
    # Two pictures of the same numbers: which rows are biggest, and — when the
    # report has a time axis — how the total moved across it.
    #
    # Plain elements sized in percentages rather than a charting library: the
    # slim image has no frontend build to hang one off, and a bar is a box.
    # It also means the chart inherits the theme, prints, and reads to a screen
    # reader as the table it sits above.
    class ChartComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::ReportsHelper

      options :query, :result

      TOP_ROWS = 8

      def render?
        result.nodes.any?
      end

      def top_nodes
        @top_nodes ||= result.nodes.first(TOP_ROWS)
      end

      def remaining_nodes
        result.nodes.size - top_nodes.size
      end

      def maximum
        @maximum ||= top_nodes.map { |node| node.total.to_f }.max || 0
      end

      def share(node)
        worklogs_share(node.total, maximum)
      end

      def value(node)
        worklogs_measure(node.total, query.measure)
      end

      def trend?
        query.column_dimension&.time? && result.columns.size > 1
      end

      def trend_columns
        result.columns
      end

      def trend_maximum
        @trend_maximum ||= trend_columns.map { |column| column_value(column) }.max || 0
      end

      def column_value(column)
        result.column_totals.dig(column.key, query.measure.to_sym).to_f
      end

      def trend_share(column)
        worklogs_share(column_value(column), trend_maximum)
      end

      def trend_label(column)
        column.label.short.presence || column.label.text
      end

      # A month of days is thirty labels in the space of ten; keep the ends and
      # thin the middle rather than overlapping them into mush.
      def show_trend_label?(index)
        step = [(trend_columns.size / 12.0).ceil, 1].max

        (index % step).zero? || index == trend_columns.size - 1
      end

      def trend_title(column)
        "#{trend_label(column)}: #{worklogs_measure(column_value(column), query.measure)}"
      end

      def row_title(node)
        [node.label.caption, node.label.text].compact.join(" · ")
      end

      def chart_heading
        I18n.t("worklogs.reports.top_by",
               dimension: query.row_dimensions.first.label.downcase,
               measure: I18n.t("worklogs.reports.measures.#{query.measure}").downcase)
      end
    end
  end
end
