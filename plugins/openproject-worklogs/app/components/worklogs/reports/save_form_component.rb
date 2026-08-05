module Worklogs
  module Reports
    # The body of the save/rename dialog: a name, and who else gets to see it.
    class SaveFormComponent < ApplicationComponent
      include OpTurbo::Streamable
      include ApplicationHelper
      include OpPrimer::ComponentHelpers
      include Worklogs::ReportsHelper

      FORM_ID = "worklogs-save-report-form".freeze

      options :saved_report, :query, :mode

      def form_id
        FORM_ID
      end

      def create?
        mode.to_sym == :create
      end

      def form_options
        if create?
          { url: worklogs_saved_reports_path, method: :post }
        else
          { url: worklogs_saved_report_path(saved_report), method: :patch }
        end
      end

      def name_value
        saved_report.name
      end

      def errors
        saved_report.errors.full_messages
      end

      def definition_summary
        parts = [query.period_label, grouping_summary]
        parts << I18n.t("worklogs.reports.saved.filter_summary", count: query.filter_count) if query.filters?

        parts.join(" · ")
      end

      def shared_caption
        I18n.t("worklogs.reports.saved.shared_caption")
      end

      private

      def grouping_summary
        parts = query.row_dimensions.map(&:label)
        parts << I18n.t("worklogs.reports.by_column", dimension: query.column_dimension.label) if query.column_dimension

        parts.join(" › ")
      end
    end
  end
end
