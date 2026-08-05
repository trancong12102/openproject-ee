module Worklogs
  module Timesheets
    # The four numbers a person actually acts on when they open their week:
    # how much is logged, whether they are on track *today*, how many days are
    # done, and which days are still empty.
    class StatsComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper

      options :timesheet

      delegate :week, :capacity, :user, to: :timesheet

      def logged
        timesheet.total
      end

      # Whole-week capacity for a past or future week, capacity up to today for
      # the current one — see Capacity#expected_so_far.
      def expected
        @expected ||= capacity.expected_so_far
      end

      def difference
        (logged - expected).round(2)
      end

      def progress
        return 0 if capacity.total.zero?

        [(logged / capacity.total * 100).round, 100].min
      end

      # Where "on track for today" sits on the progress bar, so the bar answers
      # "am I behind?" and not just "how full is the week?".
      # A marker pinned at either end says nothing: at 0% the week has not
      # started, at 100% there is nothing left to be on track for.
      def expected_marker
        return nil if capacity.total.zero? || expected.zero? || expected >= capacity.total

        (expected / capacity.total * 100).round
      end

      def difference_scheme
        return :muted if difference.zero?

        difference.negative? ? :danger : :attention
      end

      def difference_label
        return I18n.t("worklogs.stats.on_track") if difference.zero?

        prefix = difference.positive? ? "+" : "−"
        "#{prefix}#{worklogs_duration(difference.abs)}"
      end

      def complete_days
        capacity.working_days.count { |date| timesheet.daily_total(date) >= capacity.hours_for(date) }
      end

      def working_days_count
        capacity.working_days.size
      end

      # Working days already past (today included) with nothing logged at all —
      # the one thing a timesheet reminder would nag about.
      def missing_days
        @missing_days ||= capacity.working_days
                                  .select { |date| date <= Time.zone.today && timesheet.daily_total(date).zero? }
      end

      def missing_label
        return I18n.t("worklogs.stats.nothing_missing") if missing_days.empty?

        missing_days.map { |date| worklogs_day_name(date) }.join(", ")
      end

      def missing_scheme
        missing_days.empty? ? :success : :attention
      end
    end
  end
end
