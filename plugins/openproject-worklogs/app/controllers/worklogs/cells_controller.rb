module Worklogs
  # Single upsert endpoint behind every grid cell: a value creates or updates a
  # time entry, an empty value deletes it. All writes go through the core
  # TimeEntries services so contracts, journals, costs and notifications behave
  # exactly as they do in the rest of OpenProject.
  class CellsController < ApplicationController
    include Worklogs::TimesheetHelper

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_target_user
    before_action :load_entity
    before_action :load_span
    before_action :reject_locked_period

    def create
      result = save_cell

      if result.success?
        render json: cell_payload(result.result)
      else
        render json: { message: result.errors.full_messages.join(", ") }, status: :unprocessable_content
      end
    end

    private

    # The contracts refuse this too, whichever page it comes from. Saying so
    # here means the grid gets the reason rather than a generic refusal.
    def reject_locked_period
      return unless PeriodLock.locked?(user_id: @user.id, on: date)

      render json: { message: I18n.t("worklogs.approval.error_cell_locked") },
             status: :unprocessable_content
    end

    def save_cell
      entry = existing_entry

      if hours.nil? || hours.zero?
        return ServiceResult.success if entry.nil?

        TimeEntries::DeleteService.new(model: entry, user: current_user).call
      elsif entry
        TimeEntries::UpdateService.new(model: entry, user: current_user).call(hours:)
      else
        create_entry
      end
    end

    def create_entry
      unless policy.may_log?(@entity)
        return ServiceResult.failure(errors: error_for(:error_unable_to_update_time_entry))
      end

      TimeEntries::CreateService
        .new(user: current_user)
        .call(user: @user,
              entity: @entity,
              project: @entity.project,
              spent_on: date,
              hours:,
              activity_id: params[:activity_id].presence)
    end

    def existing_entry
      return nil if params[:entry_id].blank?

      entry = TimeEntry.find_by(id: params[:entry_id], user_id: @user.id, spent_on: date)
      return nil if entry.nil?

      # Never let a stale client id move time onto a different row.
      return nil unless entry.entity == @entity && entry.activity_id.to_s == params[:activity_id].to_s

      entry
    end

    # The grid recomputes its totals from a freshly built timesheet rather than
    # trusting the browser's arithmetic.
    def cell_payload(entry)
      timesheet = self.timesheet
      activity = row_activity(entry)
      row = timesheet.rows.find { |candidate| candidate.key == Row.key_for(@entity, activity) }
      capacity_total = timesheet.capacity.total

      {
        stats: stats_payload(timesheet),
        day_difference: day_difference(timesheet, date),
        span_difference: span_difference_payload(timesheet),
        # A destroyed entry must not leave its id behind on the client, or the
        # next keystroke in that cell would try to update a deleted record.
        entry_id: (entry.id if entry.is_a?(TimeEntry) && !entry.destroyed?),
        # Creating an entry without an activity makes OpenProject fill in the
        # project default, which moves the row to a different key. Hand both
        # back so the grid can re-point the row it just edited.
        activity_id: activity&.id,
        row_key: Row.key_for(@entity, activity),
        hours: hours || 0,
        row_total: row&.total || 0,
        day_total: timesheet.daily_total(date),
        span_total: timesheet.total,
        capacity_total:,
        progress: capacity_total.zero? ? 0 : [(timesheet.total / capacity_total * 100).round, 100].min
      }
    end

    # The stats strip lives outside the grid, so a saved cell has to carry its
    # own refreshed figures — the alternative is a second round trip per
    # keystroke just to re-render four numbers.
    def stats_payload(timesheet)
      stats = Timesheets::StatsComponent.new(timesheet:)

      {
        logged: worklogs_duration(stats.logged),
        progress: stats.progress,
        expected_marker: stats.expected_marker,
        difference_label: stats.difference_label,
        difference_scheme: stats.difference_scheme,
        complete_days: stats.complete_days,
        missing_label: stats.missing_label,
        missing_scheme: stats.missing_scheme
      }
    end

    # Mirrors GridComponent#day_difference_label / #span_difference_label; the
    # footer row has to move with the cell that was just saved.
    def day_difference(timesheet, on)
      target = timesheet.capacity.hours_for(on)
      return { label: "", state: "-none" } if target.zero?

      signed_difference(timesheet.daily_total(on) - target)
    end

    def span_difference_payload(timesheet)
      signed_difference(timesheet.total - timesheet.capacity.total)
    end

    def signed_difference(value)
      value = value.round(2)
      return { label: "0", state: "-met" } if value.zero?

      { label: "#{value.negative? ? '−' : '+'}#{worklogs_hours(value.abs)}",
        state: value.negative? ? "-under" : "-over" }
    end

    def row_activity(entry)
      if entry.is_a?(TimeEntry) && !entry.destroyed?
        entry.activity
      else
        TimeEntryActivity.find_by(id: params[:activity_id])
      end
    end

    def policy
      @policy ||= Policy.new(viewer: current_user, subject: @user)
    end

    def hours
      return nil if params[:hours].blank?

      params[:hours].to_f.round(2)
    end

    def date
      @date ||= Date.iso8601(params[:date])
    rescue Date::Error
      render_400
    end

    def load_target_user
      @user = params[:user_id].present? ? User.find(params[:user_id]) : current_user
      render_403 unless Policy.new(viewer: current_user, subject: @user).may_view?
    end

    def load_entity
      klass = params[:entity_type].to_s.safe_constantize
      return render_400 unless TimeEntry::ALLOWED_ENTITY_TYPES.include?(params[:entity_type].to_s)

      @entity = klass.visible(current_user).find_by(id: params[:entity_id])
      render_404 if @entity.nil?
    end

    # The span the grid is showing, and the filters it is showing it under, so
    # the totals sent back are the totals the page is displaying. `span_date`
    # rather than `date`, because `date` here is the cell's.
    def load_span
      @span = Span.for_kind(params[:span], params[:span_date])
    end

    def timesheet
      Timesheet.new(user: @user, span: @span, viewer: current_user,
                    project_ids: id_list(:project_ids), activity_ids: id_list(:activity_ids))
    end

    def id_list(name)
      Array(params[name]).flat_map { |value| value.to_s.split(",") }
                         .filter_map { |value| Integer(value, exception: false) }
                         .uniq
    end

    def error_for(message_key)
      errors = ActiveModel::Errors.new(TimeEntry.new)
      errors.add(:base, I18n.t(message_key, default: I18n.t("worklogs.timesheet.save_failed")))
      errors
    end
  end
end
