module Worklogs
  module Homescreen
    # "Where is my week" on the OpenProject home page.
    #
    # Deliberately a *server-rendered* block on the homescreen rather than a My
    # Page widget: My Page widgets are Angular components in a precompiled
    # bundle this image cannot rebuild, so a widget there is not something a
    # plugin can add at all. The homescreen has a real view hook, and the
    # question people open a dashboard to answer — "am I behind, and on which
    # day" — is the same either way.
    #
    # It answers in one glance and then gets out of the way: three numbers, the
    # days that are still empty, and a link to the week they belong to.
    class BlockComponent < ApplicationComponent
      include Worklogs::TimesheetHelper

      def render?
        User.current.logged? && User.current.allowed_globally?(:view_worklogs)
      end

      def user = User.current

      def week
        @week ||= Week.current
      end

      def timesheet
        @timesheet ||= Timesheet.new(user:, span: week, viewer: user)
      end

      delegate :capacity, :submission, to: :timesheet

      def logged = timesheet.total

      # Capacity up to today, not the whole week: "you are 24 hours short" every
      # Monday morning is the fastest way to make somebody stop reading a page.
      def expected = @expected ||= capacity.expected_so_far

      def difference = (logged - expected).round(2)

      def progress
        return 0 if capacity.total.zero?

        [(logged / capacity.total * 100).round, 100].min
      end

      def difference_scheme
        return :muted if difference.zero?

        difference.negative? ? :danger : :success
      end

      def difference_label
        return I18n.t("worklogs.stats.on_track") if difference.zero?

        "#{difference.positive? ? '+' : '−'}#{worklogs_duration(difference.abs)}"
      end

      # Working days that have already happened and are still empty. A day in
      # the future is not missing, it just has not arrived.
      def missing_days
        @missing_days ||= capacity.working_days
                                  .select { |date| date <= Time.zone.today && timesheet.daily_total(date).zero? }
      end

      def missing_label
        return I18n.t("worklogs.stats.nothing_missing") if missing_days.empty?

        missing_days.map { |date| worklogs_day_name(date) }.join(", ")
      end

      # Only the three states that tell somebody something they did not already
      # know. "Withdrawn" and "reopened" both mean the week is open again, which
      # is what a week with no badge on it means anyway — and in the withdrawn
      # case the person reading this is the one who did it.
      SHOWN_STATUSES = %w[submitted approved rejected].freeze

      SCHEMES = { "submitted" => :accent, "approved" => :success, "rejected" => :danger }.freeze

      def status_scheme
        SCHEMES.fetch(submission.status, :attention)
      end

      def show_status?
        Settings.approvals_enabled? && SHOWN_STATUSES.include?(submission&.status)
      end

      def coverage?
        User.current.allowed_globally?(:view_worklogs_coverage)
      end
    end
  end
end
