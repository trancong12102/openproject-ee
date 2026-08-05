module Worklogs
  # Every state change a submission can go through, in one place, each one
  # writing its own line of the trail in the same transaction that makes it.
  #
  # Deliberately not five controllers each doing it their own way: the trail is
  # only worth having if nothing can change a submission without leaving a mark.
  class SubmissionService
    attr_reader :actor

    def initialize(actor:)
      @actor = actor
    end

    def submit(user:, week:, note: nil)
      submission = Submission.find_or_initialize_by(user_id: user.id, period_start: week.start_date)

      unless submittable?(submission, user)
        return refuse(submission, :error_worklogs_not_submittable)
      end

      submission.assign_attributes(period_end: week.end_date, status: "submitted",
                                   submitted_by: actor, submitted_at: Time.zone.now,
                                   note:, decided_by: nil, decided_at: nil, decision_note: nil,
                                   hours: logged_hours(user, week))

      commit(submission, "submitted", note)
    end

    def withdraw(submission, note: nil)
      return refuse(submission, :error_worklogs_not_withdrawable) unless submission.withdrawable_by?(actor)

      submission.assign_attributes(status: "withdrawn", decided_by: actor, decided_at: Time.zone.now,
                                   decision_note: note)

      commit(submission, "withdrawn", note)
    end

    def approve(submission, note: nil)
      return refuse(submission, :error_worklogs_not_decidable) unless submission.decidable_by?(actor)

      decide(submission, "approved", note)
    end

    def reject(submission, note: nil)
      return refuse(submission, :error_worklogs_not_decidable) unless submission.decidable_by?(actor)

      decide(submission, "rejected", note)
    end

    # Unlocking a week somebody already signed off. Kept separate from reject so
    # the trail can tell "sent back before approval" from "opened again after",
    # which are very different things to find in an audit six months later.
    def reopen(submission, note: nil)
      return refuse(submission, :error_worklogs_not_reopenable) unless submission.reopenable_by?(actor)

      submission.assign_attributes(status: "reopened", decided_by: actor, decided_at: Time.zone.now,
                                   decision_note: note)

      commit(submission, "reopened", note)
    end

    private

    def submittable?(submission, user)
      return false unless actor.id == user.id || actor.admin?

      submission.new_record? || submission.open?
    end

    def decide(submission, status, note)
      submission.assign_attributes(status:, decided_by: actor, decided_at: Time.zone.now,
                                   decision_note: note,
                                   hours: logged_hours(submission.user, submission.week))

      commit(submission, status, note)
    end

    def commit(submission, action, note)
      Submission.transaction do
        submission.save!
        submission.events.create!(user: actor, action:, note:, hours: submission.hours)
      end

      submission
    rescue ActiveRecord::RecordInvalid
      submission
    end

    def refuse(submission, message)
      submission.errors.add(:base, I18n.t("worklogs.approval.#{message}"))
      submission
    end

    # The real total, not the actor's view of it: an approval records what the
    # week contains, and permissions must not be able to change that number.
    def logged_hours(user, week)
      TimeEntry.where(user_id: user.id, spent_on: week.start_date..week.end_date).sum(:hours).to_f.round(2)
    end
  end
end
