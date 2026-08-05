module Worklogs
  # Rows the user puts on a sheet before logging into them. A row is just a
  # (work package, activity) pin — no zero-hour time entries are created, so
  # nothing leaks into reports, invoices or the work package's spent time.
  #
  # Pins are weekly even when the sheet is a month: a month collects every
  # week's pins, and a row added to a month lands in the week the person is
  # most likely to fill in — the current one, if the month contains it.
  class RowsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_span, :load_user
    before_action :reject_locked_period, except: %i[new]

    def new
      @row_pin = RowPin.new(user: @user, week_start: pin_week.start_date, entity_type: "WorkPackage")

      respond_with_dialog(
        Worklogs::Timesheets::AddRowDialogComponent.new(row_pin: @row_pin, context:)
      )
    end

    def create
      @row_pin = RowPin.new(row_pin_attributes)

      if @row_pin.save
        close_dialog_via_turbo_stream("##{Worklogs::Timesheets::AddRowDialogComponent::DIALOG_ID}")
        refresh_grid
      else
        update_via_turbo_stream(
          component: Worklogs::Timesheets::AddRowFormComponent.new(row_pin: @row_pin, context:),
          status: :bad_request
        )
      end

      respond_with_turbo_streams
    end

    # Drops the row's pin only. Time entries are never touched here — the grid
    # only offers this on rows with no hours, and deleting logged time stays an
    # explicit act (clear the cell, or use the entry dialog).
    #
    # Across every week of the span, because the × sits on a row a month drew
    # from all of them: unpinning one week would leave the row on screen.
    def destroy
      entity_type, entity_id, activity_id = params[:id].split("-")

      RowPin.where(user_id: @user.id,
                   week_start: @span.weeks.map(&:start_date),
                   entity_type:,
                   entity_id:,
                   activity_id: (activity_id unless activity_id == "none"))
            .destroy_all

      refresh_grid
      respond_with_turbo_streams
    end

    # Rebuilds the previous span's row structure on this one, without its hours.
    def copy_previous
      previous = Timesheet.new(user: @user, span: @span.previous, viewer: current_user)

      previous.rows.each do |row|
        RowPin.find_or_create_by(user_id: @user.id,
                                 week_start: pin_week.start_date,
                                 entity_type: row.entity.class.name,
                                 entity_id: row.entity.id,
                                 activity_id: row.activity&.id)
      end

      refresh_grid
      respond_with_turbo_streams
    end

    private

    # Rows are only pins, but a locked week should not be rearranged either:
    # an approver came back to a page and found a row that was not there when
    # they approved it is exactly the confusion locking is for.
    def reject_locked_period
      return unless PeriodLock.locked?(user_id: @user.id, on: pin_week.start_date)

      render_403 message: I18n.t("worklogs.approval.error_cell_locked")
    end

    # Which week a new pin belongs to. A week sheet has only one; a month puts
    # it in the week you are living in, falling back to the month's first.
    def pin_week
      @pin_week ||= if @span.week?
                      @span
                    else
                      Week.containing(@span.include?(Time.zone.today) ? Time.zone.today : @span.start_date)
                    end
    end

    def refresh_grid
      update_via_turbo_stream(component: Worklogs::Timesheets::GridComponent.new(timesheet:))
    end

    def timesheet
      Timesheet.new(user: @user, span: @span, viewer: current_user,
                    project_ids: id_list(:project_ids), activity_ids: id_list(:activity_ids))
    end

    # What every link out of this controller has to carry, so the sheet the
    # user came from is the sheet they are handed back.
    def context
      @context ||= { date: @span.to_param, user_id: @user.id,
                     project_ids: id_list(:project_ids), activity_ids: id_list(:activity_ids) }
                   .merge(@span.month? ? { span: @span.kind } : {})
                   .compact_blank
    end

    def row_pin_attributes
      {
        user_id: @user.id,
        week_start: pin_week.start_date,
        entity_type: "WorkPackage",
        entity_id: params.dig(:worklogs_row_pin, :entity_id).presence || params[:entity_id],
        activity_id: params.dig(:worklogs_row_pin, :activity_id).presence || params[:activity_id].presence
      }
    end

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
