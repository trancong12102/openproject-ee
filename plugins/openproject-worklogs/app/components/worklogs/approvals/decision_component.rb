module Worklogs
  module Approvals
    # The decision itself, plus everything that has already happened to this
    # submission.
    #
    # Approve and reject share one note field rather than two forms: the note
    # explains the decision, whichever way it goes.
    class DecisionComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include OpPrimer::ComponentHelpers

      options :submission, :timesheet

      def decidable?
        submission.decidable_by?(User.current)
      end

      def reopenable?
        submission.reopenable_by?(User.current)
      end

      def self_approval?
        submission.user_id == User.current.id
      end

      def href
        worklogs_approval_path(submission)
      end

      def submitted_summary
        I18n.t("worklogs.approval.submitted_summary",
               name: (submission.submitted_by || submission.user).name,
               when: I18n.l(submission.submitted_at.to_date, format: :long))
      end

      def note
        submission.note.presence
      end

      def events
        submission.events.includes(:user)
      end

      def event_time(event)
        I18n.l(event.created_at.to_date, format: :long)
      end

      # The snapshot against what the week holds right now. They can differ
      # after a reopen, and an approver looking at a stale figure would be the
      # worst possible time to find that out.
      def drifted?
        submission.hours.to_f.round(2) != timesheet.total.round(2)
      end

      def drift_label
        I18n.t("worklogs.approval.drifted",
               submitted: worklogs_duration(submission.hours),
               current: worklogs_duration(timesheet.total))
      end
    end
  end
end
