module Worklogs
  class TimesheetsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_span, :load_user

    menu_item :worklogs_timesheet

    layout "global"

    def index
      @timesheet = timesheet
    end

    # Bare stats + grid fragment, no layout: the browser swaps both in after a
    # core time entry dialog reports a change. The stats strip has to come along
    # or the total would keep claiming whatever it said before the dialog.
    def grid
      @timesheet = timesheet

      render "grid", layout: false
    end

    private

    def timesheet
      Timesheet.new(user: @user, span: @span, viewer: current_user,
                    project_ids: id_list(:project_ids), activity_ids: id_list(:activity_ids))
    end

    # A week or a month, and which one. Anything unrecognised is this week —
    # the URL is user-editable, and a typo should land on the ordinary view.
    def load_span
      @span = Span.from_params(params)
    end

    def id_list(name)
      Array(params[name]).flat_map { |value| value.to_s.split(",") }
                         .filter_map { |value| Integer(value, exception: false) }
                         .uniq
    end

    def load_user
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user

      render_403 unless Policy.new(viewer: current_user, subject: @user).may_view?
    end
  end
end
