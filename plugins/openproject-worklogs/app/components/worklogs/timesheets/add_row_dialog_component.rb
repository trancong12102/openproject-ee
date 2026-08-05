module Worklogs
  module Timesheets
    # Puts an empty row on the sheet so the user can plan first and log later.
    class AddRowDialogComponent < ApplicationComponent
      include ApplicationHelper
      include OpTurbo::Streamable
      include OpPrimer::ComponentHelpers

      DIALOG_ID = "worklogs-add-row-dialog".freeze

      options :row_pin, :context

      private

      def dialog_title
        I18n.t("worklogs.timesheet.add_row")
      end
    end
  end
end
