module Worklogs
  # The nudge. One mail, one week, addressed to the person who can fix it.
  #
  # Deliberately not a digest to a manager: a list of everybody's gaps sent to
  # somebody else is a report, and this plugin already has a page for that.
  class ReminderMailer < ApplicationMailer
    helper Worklogs::TimesheetHelper

    def missing_time(user, week_start)
      @user = user
      @week = Week.new(week_start.to_date)
      @timesheet = Timesheet.new(user: @user, week: @week, viewer: @user)
      @row = summary

      open_project_headers User: user.name

      with_locale_for(user) do
        mail(to: user, subject: subject_line)
      end
    end

    private

    Summary = Struct.new(:logged, :capacity, :missing, :empty_days, keyword_init: true)

    def summary
      capacity = @timesheet.capacity
      empty = @week.dates.select do |date|
        capacity.hours_for(date).positive? && @timesheet.daily_total(date).zero?
      end

      Summary.new(logged: @timesheet.total,
                  capacity: capacity.total,
                  missing: [(capacity.total - @timesheet.total).round(2), 0].max,
                  empty_days: empty)
    end

    def subject_line
      I18n.t("worklogs.reminders.subject",
             app: Setting.app_title,
             week: I18n.t("worklogs.timesheet.week_number", number: @week.start_date.cweek))
    end
  end
end
