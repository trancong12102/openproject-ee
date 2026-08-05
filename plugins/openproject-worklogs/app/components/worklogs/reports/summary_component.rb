module Worklogs
  module Reports
    # The report in one line, before the table: what was counted, over how long,
    # spread across how many people and projects.
    class SummaryComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::ReportsHelper

      options :query, :result

      Figure = Struct.new(:label, :value, :caption, keyword_init: true)

      def headline
        worklogs_measure(result.grand_total, query.measure)
      end

      def headline_label
        I18n.t("worklogs.reports.measures.#{query.measure}")
      end

      def period_caption
        "#{query.period_label} · #{days} #{I18n.t('worklogs.reports.days', count: days)}"
      end

      # The headline already says one of these; repeating it beside itself just
      # takes up the space another figure could have used.
      def figures
        [
          *hours_figure,
          *entries_figure,
          Figure.new(label: I18n.t("worklogs.reports.average_day"),
                     value: worklogs_duration(average_per_day),
                     caption: I18n.t("worklogs.reports.average_day_caption")),
          *cost_figure
        ]
      end

      def rows_label
        I18n.t("worklogs.reports.rows_summary",
               count: result.nodes.size,
               dimension: query.row_dimensions.first.label.downcase)
      end

      private

      def days
        (query.to - query.from).to_i + 1
      end

      # Spread over the days that were actually worked, not over every day in
      # the range: a monthly report divided by 31 tells nobody anything.
      def average_per_day
        worked = result.totals[:entries].zero? ? 0 : days_with_time
        return 0 if worked.zero?

        (result.totals[:hours] / worked).round(2)
      end

      def days_with_time
        @days_with_time ||= result.scope.relation.distinct.count(:spent_on)
      end

      def hours_figure
        return [] if query.measure == "hours"

        [Figure.new(label: I18n.t("worklogs.reports.measures.hours"),
                    value: worklogs_duration(result.totals[:hours]),
                    caption: I18n.t("worklogs.reports.hours_caption"))]
      end

      def entries_figure
        return [] if query.measure == "entries"

        [Figure.new(label: I18n.t("worklogs.reports.measures.entries"),
                    value: number_with_delimiter(result.totals[:entries]),
                    caption: I18n.t("worklogs.reports.entries_caption"))]
      end

      def cost_figure
        return [] if query.measure == "costs" || !result.scope.costs_visible?

        [Figure.new(label: I18n.t("worklogs.reports.measures.costs"),
                    value: worklogs_currency(result.totals[:costs]),
                    caption: I18n.t("worklogs.reports.costs_caption"))]
      end
    end
  end
end
