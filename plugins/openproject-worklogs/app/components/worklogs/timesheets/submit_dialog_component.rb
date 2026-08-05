module Worklogs
  module Timesheets
    class SubmitDialogComponent < ApplicationComponent
      include OpTurbo::Streamable
      include ApplicationHelper
      include OpPrimer::ComponentHelpers
      include Worklogs::TimesheetHelper

      DIALOG_ID = "worklogs-submit-dialog".freeze

      options :submission, :week, :user, :timesheet

      def dialog_id
        DIALOG_ID
      end

      def dialog_title
        I18n.t("worklogs.approval.submit_title",
               week: I18n.t("worklogs.timesheet.week_number", number: week.start_date.cweek))
      end

      def subtitle
        worklogs_week_range(week)
      end
    end
  end
end
