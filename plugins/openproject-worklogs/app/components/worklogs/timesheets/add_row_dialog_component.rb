module Worklogs
  module Timesheets
    # Puts an empty row on the week so the user can plan first and log later.
    class AddRowDialogComponent < ApplicationComponent
      include ApplicationHelper
      include OpTurbo::Streamable
      include OpPrimer::ComponentHelpers

      DIALOG_ID = "worklogs-add-row-dialog".freeze

      options :row_pin, :week, :user

      private

      def dialog_title
        I18n.t("worklogs.timesheet.add_row")
      end
    end
  end
end
