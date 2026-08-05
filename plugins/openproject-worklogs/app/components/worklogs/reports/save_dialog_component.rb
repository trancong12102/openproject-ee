module Worklogs
  module Reports
    # Wraps the save/rename form. Same form either way — the difference between
    # saving a new report and renaming one is the verb on the button.
    class SaveDialogComponent < ApplicationComponent
      include OpTurbo::Streamable
      include ApplicationHelper
      include OpPrimer::ComponentHelpers

      DIALOG_ID = "worklogs-save-report-dialog".freeze

      options :saved_report, :query, :mode

      def dialog_id
        DIALOG_ID
      end

      def dialog_title
        I18n.t("worklogs.reports.saved.#{create? ? 'save_title' : 'rename_title'}")
      end

      def submit_label
        I18n.t("worklogs.reports.saved.#{create? ? 'save_submit' : 'rename_submit'}")
      end

      def create?
        mode.to_sym == :create
      end
    end
  end
end
