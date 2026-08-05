module Worklogs
  # Aggregates one user's time entries for one week into the grid structure:
  # rows grouped by project, cells keyed by date, plus totals and capacity.
  class Timesheet
    Group = Struct.new(:project, :rows, keyword_init: true) do
      def total
        rows.sum(&:total)
      end
    end

    attr_reader :user, :week, :viewer

    def initialize(user:, week:, viewer: User.current)
      @user = user
      @week = week
      @viewer = viewer
    end

    def rows
      @rows ||= build_rows
    end

    def groups
      @groups ||= rows
                    .group_by(&:project)
                    .map { |project, project_rows| Group.new(project:, rows: project_rows) }
                    .sort_by { |group| group.project&.name.to_s }
    end

    def daily_total(date)
      daily_totals[date] || 0.0
    end

    def daily_totals
      @daily_totals ||= week.dates.index_with { |date| rows.sum { |row| row.cell(date).hours } }
    end

    def total
      rows.sum(&:total)
    end

    def capacity
      @capacity ||= Capacity.new(user:, week:)
    end

    def policy
      @policy ||= Policy.new(viewer:, subject: user)
    end

    def empty?
      rows.empty?
    end

    private

    def build_rows
      grouped = time_entries.group_by { |entry| [entry.entity, entry.activity] }

      rows = grouped.map do |(entity, activity), entries|
        row = Row.new(entity:, activity:)
        entries.group_by(&:spent_on).each do |date, day_entries|
          row.cells[date] = Cell.new(date:, entries: day_entries, row:)
        end
        row
      end

      (rows + pinned_rows(rows)).sort_by(&:sort_key)
    end

    # Rows the user added to the week but has not filled in yet. Without them,
    # "add row" and "copy last week" would lose their result on every reload.
    def pinned_rows(existing_rows)
      taken = existing_rows.map(&:key).to_set

      RowPin
        .where(user_id: user.id, week_start: week.start_date)
        .includes(:activity)
        .filter_map do |pin|
          entity = pin.entity
          next if entity.nil?

          row = Row.new(entity:, activity: pin.activity)
          next if taken.include?(row.key)

          row
        end
    end

    def time_entries
      @time_entries ||= TimeEntry
                          .where(user_id: user.id, spent_on: week.range)
                          .includes(:activity, :project, entity: :project)
                          .order(:spent_on, :start_time, :id)
                          .select { |entry| entry.entity.present? && entry.visible_by?(viewer) }
    end
  end
end
