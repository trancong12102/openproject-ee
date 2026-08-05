module Worklogs
  # Handing a week in, and taking it back before anybody has looked at it.
  class SubmissionsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :require_approvals_enabled
    before_action :load_week, :load_user

    def new
      @submission = Submission.find_or_initialize_by(user_id: @user.id, period_start: @week.start_date)

      respond_with_dialog(
        Timesheets::SubmitDialogComponent.new(submission: @submission, week: @week, user: @user,
                                              timesheet:)
      )
    end

    def create
      @submission = service.submit(user: @user, week: @week, note: params[:note].presence)

      if @submission.errors.empty?
        close_dialog_via_turbo_stream("##{Timesheets::SubmitDialogComponent::DIALOG_ID}")
        refresh_timesheet
      else
        render_dialog_errors
      end

      respond_with_turbo_streams
    end

    # Taking a week back off the pile. Only possible while nobody has decided
    # on it — once it is approved, only an approver can open it again.
    def destroy
      @submission = Submission.find_by!(user_id: @user.id, period_start: @week.start_date)
      service.withdraw(@submission)

      refresh_timesheet
      respond_with_turbo_streams
    end

    private

    def require_approvals_enabled
      render_404 unless Settings.approvals_enabled?
    end

    def service
      @service ||= SubmissionService.new(actor: current_user)
    end

    def timesheet
      @timesheet ||= Timesheet.new(user: @user, span: @week, viewer: current_user)
    end

    # The sub-header goes too: submitting takes "Add row" and "Log time" away,
    # and a button that stays on screen after it stopped working is worse than
    # a page that redraws a little more than it strictly had to.
    def refresh_timesheet
      update_via_turbo_stream(component: Timesheets::SubHeaderComponent.new(timesheet:))
      update_via_turbo_stream(component: Timesheets::StatusComponent.new(timesheet:))
      update_via_turbo_stream(component: Timesheets::GridComponent.new(timesheet:))
    end

    def render_dialog_errors
      update_via_turbo_stream(
        component: Timesheets::SubmitFormComponent.new(submission: @submission, week: @week,
                                                       user: @user, timesheet:),
        status: :bad_request
      )
    end

    def load_week
      @week = Week.from_param(params[:date])
    end

    # Submitting is the owner's act. An administrator may do it for somebody
    # who has left, and that is recorded in the trail as their doing.
    def load_user
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user

      render_403 unless @user == current_user || current_user.admin?
    end
  end
end
