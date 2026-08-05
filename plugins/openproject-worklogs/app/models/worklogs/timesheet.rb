module Worklogs
  # Aggregates one user's time entries over one span — a week or a month — into
  # the grid structure: rows grouped by project, cells keyed by date, plus
  # totals and capacity.
  #
  # The span is asked for dates and nothing else, so a month is a wider grid
  # and not a second implementation. The two things that are genuinely weekly,
  # submitting and pinned rows, go through `span.weeks`.
  class Timesheet
    Group = Struct.new(:project, :rows, keyword_init: true) do
      def total
        rows.sum(&:total)
      end
    end

    attr_reader :user, :span, :viewer, :project_ids, :activity_ids

    def initialize(user:, span:, viewer: User.current, project_ids: [], activity_ids: [])
      @user = user
      @span = span
      @viewer = viewer
      @project_ids = Array(project_ids).map(&:to_i)
      @activity_ids = Array(activity_ids).map(&:to_i)
    end

    delegate :dates, :weeks, to: :span

    def filtered?
      project_ids.any? || activity_ids.any?
    end

    def filter_count
      project_ids.size + activity_ids.size
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
      @daily_totals ||= dates.index_with { |date| rows.sum { |row| row.cell(date).hours } }
    end

    def total
      rows.sum(&:total)
    end

    def capacity
      @capacity ||= Capacity.new(user:, span:)
    end

    def policy
      @policy ||= Policy.new(viewer:, subject: user)
    end

    # Keyed by the week it covers, because that is how a submission is keyed
    # and how the month view lists them.
    def submissions
      @submissions ||= Submission
                         .where(user_id: user.id, period_start: weeks.map(&:start_date))
                         .index_by(&:period_start)
    end

    def submission_for(week)
      submissions[week.start_date]
    end

    # The submission, for a week. A month has several and the caller has to say
    # which — asking a month for "the" submission is a question with no answer.
    def submission
      submission_for(span) if span.week?
    end

    # Whether the day this cell sits on is closed. Per date rather than per
    # sheet, because a month can be half signed off: the first two weeks
    # approved and the rest still open is the ordinary state of a month you are
    # looking at on the 20th.
    def locked_on?(date)
      week = weeks.find { |candidate| candidate.include?(date) }

      submission_for(week)&.locked? || false
    end

    # Closed all the way through. What the "add a row" and "log time" buttons
    # ask before offering themselves: on a month with one open week left there
    # is still somewhere to put an hour.
    def locked?
      weeks.all? { |week| submission_for(week)&.locked? }
    end

    def any_locked?
      weeks.any? { |week| submission_for(week)&.locked? }
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

    # Rows the user added to the span but has not filled in yet. Without them,
    # "add row" and "copy last week" would lose their result on every reload.
    #
    # Pins are weekly; a month collects every week's, so a row pinned in one
    # week of the month is on the month's grid too.
    def pinned_rows(existing_rows)
      taken = existing_rows.map(&:key).to_set

      RowPin
        .where(user_id: user.id, week_start: weeks.map(&:start_date))
        .includes(:activity)
        .filter_map do |pin|
          entity = pin.entity
          next if entity.nil?

          row = Row.new(entity:, activity: pin.activity)
          next if taken.include?(row.key) || !pinned_row_visible?(row)

          taken << row.key
          row
        end
    end

    # A filtered grid filters its empty rows too, or filtering by one project
    # would still show every row you had pinned in another.
    def pinned_row_visible?(row)
      return false if project_ids.any? && !project_ids.include?(row.project&.id)
      return false if activity_ids.any? && !activity_ids.include?(row.activity&.id)

      true
    end

    def time_entries
      @time_entries ||= filtered_entries
                          .includes(:activity, :project, entity: :project)
                          .order(:spent_on, :start_time, :id)
                          .select { |entry| entry.entity.present? && entry.visible_by?(viewer) }
    end

    def filtered_entries
      scope = TimeEntry.where(user_id: user.id, spent_on: span.range)
      scope = scope.where(project_id: project_ids) if project_ids.any?
      scope = scope.where(activity_id: activity_ids) if activity_ids.any?
      scope
    end
  end
end
