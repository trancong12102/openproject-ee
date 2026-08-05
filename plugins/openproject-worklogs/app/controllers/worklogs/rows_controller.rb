module Worklogs
  # Rows the user puts on a week before logging into them. A row is just a
  # (work package, activity) pin — no zero-hour time entries are created, so
  # nothing leaks into reports, invoices or the work package's spent time.
  class RowsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_week, :load_user

    def new
      @row_pin = RowPin.new(user: @user, week_start: @week.start_date, entity_type: "WorkPackage")

      respond_with_dialog(
        Worklogs::Timesheets::AddRowDialogComponent.new(row_pin: @row_pin, week: @week, user: @user)
      )
    end

    def create
      @row_pin = RowPin.new(row_pin_attributes)

      if @row_pin.save
        close_dialog_via_turbo_stream("##{Worklogs::Timesheets::AddRowDialogComponent::DIALOG_ID}")
        refresh_grid
      else
        update_via_turbo_stream(
          component: Worklogs::Timesheets::AddRowFormComponent.new(row_pin: @row_pin, week: @week, user: @user),
          status: :bad_request
        )
      end

      respond_with_turbo_streams
    end

    # Drops the row's pin only. Time entries are never touched here — the grid
    # only offers this on rows with no hours, and deleting logged time stays an
    # explicit act (clear the cell, or use the entry dialog).
    def destroy
      entity_type, entity_id, activity_id = params[:id].split("-")

      RowPin.where(user_id: @user.id,
                   week_start: @week.start_date,
                   entity_type:,
                   entity_id:,
                   activity_id: (activity_id unless activity_id == "none"))
            .destroy_all

      refresh_grid
      respond_with_turbo_streams
    end

    # Rebuilds last week's row structure on this week, without its hours.
    def copy_previous
      previous = Timesheet.new(user: @user, week: @week.previous, viewer: current_user)

      previous.rows.each do |row|
        RowPin.find_or_create_by(user_id: @user.id,
                                 week_start: @week.start_date,
                                 entity_type: row.entity.class.name,
                                 entity_id: row.entity.id,
                                 activity_id: row.activity&.id)
      end

      refresh_grid
      respond_with_turbo_streams
    end

    private

    def refresh_grid
      timesheet = Timesheet.new(user: @user, week: @week, viewer: current_user)
      update_via_turbo_stream(component: Worklogs::Timesheets::GridComponent.new(timesheet:))
    end

    def row_pin_attributes
      {
        user_id: @user.id,
        week_start: @week.start_date,
        entity_type: "WorkPackage",
        entity_id: params.dig(:worklogs_row_pin, :entity_id).presence || params[:entity_id],
        activity_id: params.dig(:worklogs_row_pin, :activity_id).presence || params[:activity_id].presence
      }
    end

    def load_week
      @week = Week.from_param(params[:date])
    end

    def load_user
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user

      render_403 unless Policy.new(viewer: current_user, subject: @user).may_view?
    end
  end
end
