module Worklogs
  # The other side of submitting: the weeks waiting on somebody, and what was
  # decided on the ones that are not waiting any more.
  class ApprovalsController < ApplicationController
    include OpTurbo::ComponentStream
    include Worklogs::TimesheetHelper

    helper Worklogs::TimesheetHelper

    before_action :require_login
    authorize_with_global_permission :approve_worklogs
    before_action :require_approvals_enabled

    before_action :load_submission, only: %i[show update]

    menu_item :worklogs_approvals

    layout "global"

    DECIDED_LIMIT = 25

    def index
      @pending = visible(Submission.pending.includes(:user, :submitted_by).order(period_start: :asc, id: :asc).to_a)
      @decided = visible(Submission.where.not(status: "submitted")
                                   .includes(:user, :decided_by)
                                   .order(decided_at: :desc)
                                   .limit(DECIDED_LIMIT * 2)
                                   .to_a).first(DECIDED_LIMIT)
    end

    # One week, in full: what was logged, against what capacity, and everything
    # that has happened to the submission. Approving on a total alone is
    # rubber-stamping, so the decision is made next to the detail.
    def show
      @timesheet = Timesheet.new(user: @submission.user, week: @submission.week, viewer: current_user)
    end

    def update
      service = SubmissionService.new(actor: current_user)
      note = params[:note].presence

      case params[:decision]
      when "approve" then service.approve(@submission, note:)
      when "reject" then service.reject(@submission, note:)
      when "reopen" then service.reopen(@submission, note:)
      else @submission.errors.add(:base, I18n.t("worklogs.approval.error_worklogs_not_decidable"))
      end

      if @submission.errors.any?
        flash[:error] = @submission.errors.full_messages.join(", ")
      else
        flash[:notice] = I18n.t("worklogs.approval.decision_recorded", status: @submission.status_label)
      end

      redirect_to worklogs_approval_path(@submission)
    end

    private

    # Switching approvals off has to close the door, not only hide it: a
    # bookmarked approval URL is exactly the thing that outlives a setting
    # change.
    def require_approvals_enabled
      render_404 unless Settings.approvals_enabled?
    end

    def load_submission
      @submission = Submission.includes(:user, :events).find(params[:id])

      render_403 unless may_see?(@submission)
    end

    # An approver may only see a week they could have looked at as a timesheet,
    # and only if they can see what is in it. A total with nothing behind it is
    # not something anybody should be signing off.
    def visible(submissions)
      submissions.select { |submission| may_see?(submission) }
    end

    def may_see?(submission)
      return false unless Policy.new(viewer: current_user, subject: submission.user).may_view?

      entries_visible?(submission) || week_empty?(submission)
    end

    def entries_visible?(submission)
      TimeEntry.visible(current_user)
               .where(user_id: submission.user_id, spent_on: submission.period_start..submission.period_end)
               .exists?
    end

    # An empty week is still a week somebody has to sign off; it would be
    # invisible for ever if emptiness counted as "nothing you may see".
    def week_empty?(submission)
      !TimeEntry.where(user_id: submission.user_id,
                       spent_on: submission.period_start..submission.period_end).exists?
    end
  end
end
