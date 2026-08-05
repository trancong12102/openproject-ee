module Worklogs
  module Reports
    # What was asked, written into the file next to the answer.
    #
    # A spreadsheet outlives the tab it came from, and six weeks later
    # "35h 30m of what?" has no answer at all unless the file carries the
    # question. Shared by both workbook writers so the two formats cannot end
    # up describing the same report differently.
    module ExportMetadata
      def meta_rows(grouping: true)
        rows = [[I18n.t("worklogs.reports.period"), query.period_label]]
        if grouping
          rows << [I18n.t("worklogs.reports.measure"), I18n.t("worklogs.reports.measures.#{query.measure}")]
          rows << [I18n.t("worklogs.reports.group_by"), grouping_summary]
        end
        rows << [I18n.t("worklogs.reports.filters"), filter_summary] if query.filters?
        rows << [I18n.t("worklogs.reports.generated"), generated_summary]
        rows
      end

      def grouping_summary
        parts = query.row_dimensions.map(&:label)
        parts << I18n.t("worklogs.reports.by_column", dimension: query.column_dimension.label) if query.column_dimension

        parts.join(" > ")
      end

      def filter_summary
        I18n.t("worklogs.reports.saved.filter_summary", count: query.filter_count)
      end

      def generated_summary
        "#{Time.zone.now.strftime('%Y-%m-%d %H:%M')} · #{result.viewer.name}"
      end

      # Which of the three number formats a column of measures is in. Costs are
      # money and entries are a count; everything else is hours.
      def measure_format
        case query.measure
        when "entries" then :integer
        when "costs" then :currency
        else :hours
        end
      end
    end
  end
end
