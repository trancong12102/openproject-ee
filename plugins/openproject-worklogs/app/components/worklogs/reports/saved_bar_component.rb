module Worklogs
  module Reports
    # The line above the report that says which saved report you are looking at,
    # whether you have edited it since, and what you can do about that.
    #
    # It only appears once the user has somewhere to go with it: with no saved
    # reports at all it collapses to a single "Save report" button rather than
    # taking a row of the page to say "you have nothing saved".
    class SavedBarComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::ReportsHelper
      include OpPrimer::ComponentHelpers

      options :query, :saved_report, :saved_reports, :viewer

      def mine
        @mine ||= saved_reports.select { |report| report.owned_by?(viewer) }
      end

      def shared
        @shared ||= saved_reports.reject { |report| report.owned_by?(viewer) }
      end

      def any?
        saved_reports.any?
      end

      def active?(report)
        saved_report && report.id == saved_report.id
      end

      # Whether the page has drifted from the report it was opened from. Every
      # control is a link that changes one parameter, so this is the difference
      # between "looking at Ann's report" and "looking at something of your own
      # that started as Ann's".
      def modified?
        saved_report.present? && !saved_report.matches?(query)
      end

      def editable?
        saved_report&.editable_by?(viewer)
      end

      def title
        return I18n.t("worklogs.reports.saved.unsaved") if saved_report.blank?

        saved_report.name
      end

      def owner_caption
        return nil if saved_report.blank? || saved_report.owned_by?(viewer)

        I18n.t("worklogs.reports.saved.owned_by", name: saved_report.user.name)
      end

      def save_href
        new_worklogs_saved_report_path(query.to_params)
      end

      def rename_href
        edit_worklogs_saved_report_path(saved_report, query.to_params)
      end

      def update_href
        worklogs_saved_report_path(saved_report)
      end

      def report_href(report)
        worklogs_saved_report_href(report)
      end

      def delete_confirmation
        I18n.t("worklogs.reports.saved.delete_confirm", name: saved_report.name)
      end
    end
  end
end
