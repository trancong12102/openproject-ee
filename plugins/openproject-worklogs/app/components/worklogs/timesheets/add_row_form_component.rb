module Worklogs
  module Timesheets
    # The body of the "add row" dialog: pick a work package, optionally pin the
    # activity so the row lands next to the other rows of that activity.
    class AddRowFormComponent < ApplicationComponent
      include ApplicationHelper
      include OpTurbo::Streamable
      include OpPrimer::ComponentHelpers
      include Primer::FormHelper

      FORM_ID = "worklogs-add-row-form".freeze

      options :row_pin, :context

      private

      # Carries the whole sheet — span, person, filters — so the grid that
      # comes back is the grid the row was added from.
      def submit_url_options
        { url: worklogs_rows_path(context), method: :post }
      end

      def autocompleter_url
        ::API::V3::Utilities::PathHelper::ApiV3Path.time_entries_available_work_packages_on_create
      end

      def activities
        @activities ||= TimeEntryActivity.shared.active
      end

      # Only whole-record problems belong in the banner; Primer already prints
      # per-field errors under the field they belong to.
      def base_errors
        row_pin.errors[:base]
      end
    end
  end
end
