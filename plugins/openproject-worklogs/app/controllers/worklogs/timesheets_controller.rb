module Worklogs
  class TimesheetsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_week, :load_user

    menu_item :worklogs_timesheet

    layout "global"

    def index
      @timesheet = Timesheet.new(user: @user, week: @week, viewer: current_user)
    end

    # Bare stats + grid fragment, no layout: the browser swaps both in after a
    # core time entry dialog reports a change. The stats strip has to come along
    # or the week total would keep claiming whatever it said before the dialog.
    def grid
      @timesheet = Timesheet.new(user: @user, week: @week, viewer: current_user)

      render "grid", layout: false
    end

    private

    def load_week
      @week = Week.from_param(params[:date])
    end

    def load_user
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user

      render_403 unless Policy.new(viewer: current_user, subject: @user).may_view?
    end
  end
end
