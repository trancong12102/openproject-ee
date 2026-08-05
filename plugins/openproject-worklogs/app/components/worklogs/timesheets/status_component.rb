module Worklogs
  module Timesheets
    # Where this week stands: open, waiting on somebody, signed off, or sent
    # back — and the one action that moves it on from there.
    #
    # A month has no state of its own to show, because a submission is weekly.
    # It lists the weeks it contains instead, each linking to the week where
    # the action lives — inventing a month-shaped approval that the approvals
    # queue knows nothing about would be worse than a list.
    #
    # Always rendered rather than only when something has happened. A "submit"
    # button that appears only once you already know about submitting is a
    # feature nobody finds.
    class StatusComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include OpPrimer::ComponentHelpers

      options :timesheet

      delegate :span, :user, :submission, to: :timesheet

      def render?
        return false unless Settings.approvals_enabled?
        return own? || timesheet.submissions.any? if span.month?

        own? || submission.present?
      end

      def month?
        span.month?
      end

      # One entry per week the month touches, in order, whether or not it has
      # been handed in: the empty ones are the point.
      def week_states
        span.weeks.map do |week|
          submission = timesheet.submission_for(week)

          WeekState.new(week:, submission:,
                        status: submission&.status || "open",
                        href: worklogs_timesheet_href(timesheet, week.to_params.merge(span: nil)))
        end
      end

      WeekState = Struct.new(:week, :submission, :status, :href, keyword_init: true) do
        def label
          I18n.t("worklogs.timesheet.week_number", number: week.start_date.cweek)
        end

        def status_label
          I18n.t("worklogs.approval.statuses.#{status}")
        end

        def scheme
          case status
          when "submitted" then "-waiting"
          when "approved" then "-approved"
          when "rejected", "reopened" then "-returned"
          else "-open"
          end
        end
      end

      def own?
        User.current == user
      end

      def status
        submission&.status || "open"
      end

      def status_label
        I18n.t("worklogs.approval.statuses.#{status}")
      end

      def scheme
        case status
        when "submitted" then "-waiting"
        when "approved" then "-approved"
        when "rejected", "reopened" then "-returned"
        when "withdrawn" then "-open"
        else "-open"
        end
      end

      def summary
        case status
        when "submitted" then I18n.t("worklogs.approval.summary_submitted", when: decided_or_submitted_at)
        when "approved" then I18n.t("worklogs.approval.summary_approved", name: decider, when: decided_or_submitted_at)
        when "rejected" then I18n.t("worklogs.approval.summary_rejected", name: decider, when: decided_or_submitted_at)
        when "reopened" then I18n.t("worklogs.approval.summary_reopened", name: decider, when: decided_or_submitted_at)
        when "withdrawn" then I18n.t("worklogs.approval.summary_withdrawn", when: decided_or_submitted_at)
        else I18n.t("worklogs.approval.summary_open")
        end
      end

      # The reason a week came back matters more than the fact that it did, so
      # it is shown on the timesheet rather than left in the trail.
      def decision_note
        submission&.decision_note.presence
      end

      def locked?
        timesheet.locked?
      end

      def may_submit?
        own? && !locked? && span.week?
      end

      def may_withdraw?
        submission&.withdrawable_by?(User.current) || false
      end

      def submit_href
        new_worklogs_submission_path(date: span.to_param, user_id: user.id)
      end

      def withdraw_href
        worklogs_submission_path(date: span.to_param, user_id: user.id)
      end

      def approval_href
        return nil if submission.nil? || !User.current.allowed_globally?(:approve_worklogs)

        worklogs_approval_path(submission)
      end

      def hours_summary
        return nil if submission.nil?

        I18n.t("worklogs.approval.hours_submitted", hours: worklogs_duration(submission.hours))
      end

      private

      def decider
        (submission.decided_by || submission.submitted_by)&.name.to_s
      end

      def decided_or_submitted_at
        stamp = submission.decided_at || submission.submitted_at
        return "" if stamp.nil?

        I18n.l(stamp.to_date, format: :long)
      end
    end
  end
end
