module Worklogs
  module Timesheets
    class SubHeaderComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper

      options :timesheet

      delegate :span, :user, to: :timesheet

      def title
        worklogs_span_title(span)
      end

      # One step back, one step forward, in whatever the sheet is showing:
      # a week from a week, a month from a month.
      def previous_attrs
        { href: worklogs_timesheet_href(timesheet, span.previous.to_params),
          aria: { label: I18n.t("worklogs.timesheet.previous_span") } }
      end

      def next_attrs
        { href: worklogs_timesheet_href(timesheet, span.next.to_params),
          aria: { label: I18n.t("worklogs.timesheet.next_span") } }
      end

      def today_href
        worklogs_timesheet_href(timesheet, date: "today")
      end

      def add_row_href
        new_worklogs_row_path(worklogs_timesheet_params(timesheet))
      end

      def copy_previous_href
        copy_previous_worklogs_rows_path(worklogs_timesheet_params(timesheet))
      end

      # "Copy last week" on a week, "copy last month" on a month: the button
      # says what it will actually do.
      def copy_previous_label
        I18n.t("worklogs.timesheet.copy_previous.#{span.kind}")
      end

      def copy_previous_description
        I18n.t("worklogs.timesheet.copy_previous_description.#{span.kind}")
      end

      # Logging always lands on a day inside the span being looked at, so the
      # dialog does not silently write into today when you are reviewing a past
      # week.
      def log_time_href
        date = span.include?(Time.zone.today) ? Time.zone.today : span.start_date

        dialog_time_entries_path(onlyMe: true, date: date.iso8601)
      end

      # Every "change this sheet" affordance disappears once it is closed all
      # the way through. Offering a button that the contract will refuse is
      # worse than not offering it at all — but a month with one open week left
      # still has somewhere to put an hour.
      def locked?
        timesheet.locked?
      end

      def may_log?
        !locked? && User.current == user && User.current.allowed_in_any_project?(:log_own_time)
      end
    end
  end
end
