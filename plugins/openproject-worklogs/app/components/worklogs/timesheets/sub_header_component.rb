module Worklogs
  module Timesheets
    class SubHeaderComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper

      options :timesheet

      def week
        timesheet.week
      end

      def user
        timesheet.user
      end

      def title
        "#{I18n.t('worklogs.timesheet.week_number', number: week.start_date.cweek)} · #{worklogs_week_range(week)}"
      end

      def previous_attrs
        { href: worklogs_root_path(date: week.previous.to_param),
          aria: { label: I18n.t(:label_previous_week) } }
      end

      def next_attrs
        { href: worklogs_root_path(date: week.next.to_param),
          aria: { label: I18n.t(:label_next_week) } }
      end

      def today_href
        worklogs_root_path(date: "today")
      end

      def add_row_href
        new_worklogs_row_path(date: week.to_param, user_id: user.id)
      end

      def copy_previous_href
        copy_previous_worklogs_rows_path(date: week.to_param, user_id: user.id)
      end

      # Logging always lands on a day inside the week being looked at, so the
      # dialog does not silently write into today when you are reviewing a past
      # week.
      def log_time_href
        date = week.include?(Time.zone.today) ? Time.zone.today : week.start_date

        dialog_time_entries_path(onlyMe: true, date: date.iso8601)
      end

      # Every "change this week" affordance disappears once the week is closed.
      # Offering a button that the contract will refuse is worse than not
      # offering it at all.
      def locked?
        timesheet.locked?
      end

      def may_log?
        !locked? && User.current == user && User.current.allowed_in_any_project?(:log_own_time)
      end

    end
  end
end
