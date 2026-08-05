module Worklogs
  module Timesheets
    # The weekly grid: one row per (work package, activity), one column per day.
    #
    # Every editable cell renders a real <input>, so tabbing through the week and
    # screen-reader navigation work without any JavaScript. The bundled script
    # only adds arrow-key movement, duration parsing and autosave on top.
    class GridComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper

      options :timesheet

      delegate :week, :groups, :capacity, :policy, :user, to: :timesheet

      def dates
        week.dates
      end

      def today?(date)
        date == Time.zone.today
      end

      def non_working_reason(date)
        capacity.non_working_reason(date)
      end

      def column_classes(date)
        classes = ["worklogs-grid--day"]
        classes << "-today" if today?(date)
        classes << "-non-working" if non_working_reason(date)
        classes
      end

      def cell_classes(row, cell)
        classes = column_classes(cell.date) - ["worklogs-grid--day"]
        classes.unshift("worklogs-grid--cell")
        classes << "-split" if cell.split?
        classes << "-readonly" unless editable?(row, cell)
        classes
      end

      def editable?(row, cell)
        return false if cell.split? || cell.ongoing?

        if cell.empty?
          policy.may_log?(row.entity)
        else
          policy.may_edit?(cell.entry)
        end
      end

      def cell_data(row, cell)
        {
          worklogs_cell: "",
          row: row.key,
          date: cell.date.iso8601,
          entry_id: cell.entry&.id,
          hours: worklogs_hours(cell.hours),
          entity_type: row.entity.class.name,
          entity_id: row.entity.id,
          activity_id: row.activity&.id
        }.compact
      end

      def cell_title(cell)
        return I18n.t("worklogs.timesheet.split_cell_hint") if cell.split?

        cell.comments.first
      end

      def daily_total_classes(date)
        classes = column_classes(date) - ["worklogs-grid--day"]
        classes.unshift("worklogs-grid--footer-cell")

        logged = timesheet.daily_total(date)
        target = capacity.hours_for(date)
        classes << "-over" if target.positive? && logged > target
        # Only days that have already happened can be short; colouring Friday
        # red on a Wednesday would flag every week as a problem all week.
        classes << "-under" if target.positive? && logged < target && date <= Time.zone.today
        classes
      end

      def entity_path(row)
        row.work_package? ? work_package_path(row.entity) : nil
      end

      def any_rows?
        timesheet.rows.any?
      end

      def grid_url
        worklogs_grid_path(date: week.to_param, user_id: user.id)
      end

      ENTRY_ID_PLACEHOLDER = "__entry_id__".freeze

      def entry_dialog_template
        dialog_time_entry_path(ENTRY_ID_PLACEHOLDER, onlyMe: policy.own?)
      end

      # Anything the grid itself cannot express — comment, activity, start and
      # end time, a second entry on the same day — is handed to core's own time
      # entry dialog rather than reimplemented here.
      def cell_dialog_path(row, cell)
        if cell.entry
          dialog_time_entry_path(cell.entry, onlyMe: policy.own?)
        elsif row.work_package?
          work_packages_time_entries_dialog_path(work_package_id: row.entity.id,
                                                 date: cell.date.iso8601,
                                                 onlyMe: policy.own?)
        end
      end

      # Where the cell's detail button goes once its entry is deleted from the
      # grid; handed to the browser so it can restore the link without a reload.
      def new_entry_dialog_path(row, cell)
        return nil unless row.work_package?

        work_packages_time_entries_dialog_path(work_package_id: row.entity.id,
                                               date: cell.date.iso8601,
                                               onlyMe: policy.own?)
      end

      def cell_dialog_label(row, cell)
        key = cell.empty? ? "worklogs.timesheet.log_on" : "worklogs.timesheet.open_entry"

        I18n.t(key, subject: row.subject, date: I18n.l(cell.date, format: :long))
      end

      def show_cell_dialog?(row, cell)
        return false unless cell_dialog_path(row, cell)

        cell.empty? ? policy.may_log?(row.entity) : true
      end

      def remove_row_path(row)
        worklogs_row_path(row.key, date: week.to_param, user_id: user.id)
      end

      # Only rows that hold nothing can be dropped from the week; a row with
      # hours goes away when its last cell is cleared, which keeps deleting time
      # an explicit act rather than a side effect of tidying the grid.
      def removable?(row)
        row.total.zero?
      end

      def remove_row_label(row)
        I18n.t("worklogs.timesheet.remove_row_label", subject: row.subject)
      end

      def non_working_short(date)
        reason = non_working_reason(date)
        return nil if reason.nil?

        case reason.kind
        when :holiday then I18n.t("worklogs.capacity.holiday_short")
        when :absence then I18n.t("worklogs.capacity.absence_short")
        else I18n.t("worklogs.capacity.weekend_short")
        end
      end

      # Signed gap between what was logged and what the day asked for. Days that
      # want nothing — weekend, holiday, absence — have no gap to report.
      #
      # Days still ahead of today are included on purpose: read down a column it
      # says "this day still wants 5h", which is a to-do rather than an
      # accusation, and it makes the row add up to the week figure beside it.
      # The stats strip above answers the other question, "am I behind *today*".
      def day_difference(date)
        target = capacity.hours_for(date)
        return nil if target.zero?

        (timesheet.daily_total(date) - target).round(2)
      end

      def day_difference_label(date)
        difference = day_difference(date)
        return "" if difference.nil?
        return "0" if difference.zero?

        "#{difference.negative? ? '−' : '+'}#{worklogs_hours(difference.abs)}"
      end

      def difference_classes(date)
        classes = column_classes(date) - ["worklogs-grid--day"]
        classes.unshift("worklogs-grid--footer-cell")

        difference = day_difference(date)
        classes << "-none" if difference.nil?
        classes << "-under" if difference&.negative?
        classes << "-over" if difference&.positive?
        classes << "-met" if difference&.zero?
        classes
      end

      # Deliberately the sum of the day cells to its left — the whole week's
      # capacity, not just the part of it that has already happened.
      def week_difference
        (timesheet.total - capacity.total).round(2)
      end

      def week_difference_label
        return "0" if week_difference.zero?

        "#{week_difference.negative? ? '−' : '+'}#{worklogs_hours(week_difference.abs)}"
      end

      def week_difference_class
        return "-met" if week_difference.zero?

        week_difference.negative? ? "-under" : "-over"
      end
    end
  end
end
