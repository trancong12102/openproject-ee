module Worklogs
  module Approvals
    # The list of weeks waiting on you, and the ones you have already settled.
    #
    # Ordered oldest first: the week that has been waiting longest is the one
    # somebody is being held up by.
    class QueueComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include OpPrimer::ComponentHelpers

      options :pending, :decided

      def any?
        pending.any? || decided.any?
      end

      def href(submission)
        worklogs_approval_path(submission)
      end

      def period_label(submission)
        "#{I18n.t('worklogs.timesheet.week_number', number: submission.period_start.cweek)} · " \
          "#{worklogs_week_range(Week.new(submission.period_start))}"
      end

      def waiting_label(submission)
        days = (Time.zone.today - submission.submitted_at.to_date).to_i
        return I18n.t("worklogs.approval.waiting_today") if days <= 0

        I18n.t("worklogs.approval.waiting_days", count: days)
      end

      # A week that has been sitting for over a working week is not "pending",
      # it is a problem, and the queue should say so without being asked.
      def waiting_scheme(submission)
        (Time.zone.today - submission.submitted_at.to_date).to_i >= 7 ? "-late" : ""
      end

      def hours(submission)
        worklogs_duration(submission.hours)
      end

      def status_label(submission)
        submission.status_label
      end

      def decided_summary(submission)
        return "" if submission.decided_at.nil?

        "#{submission.decided_by&.name} · #{I18n.l(submission.decided_at.to_date, format: :long)}"
      end
    end
  end
end
