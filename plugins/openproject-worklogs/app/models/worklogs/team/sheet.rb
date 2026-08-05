module Worklogs
  module Team
    # The whole team's week or month: one line per person, one column per day.
    #
    # The timesheet answers "what did I do"; the reports answer "where did the
    # time go"; coverage answers "who is behind". This answers the question a
    # manager actually opens a tab for — "what is everybody working on right
    # now" — and it is the same grid as the personal sheet with people where
    # the work packages usually are.
    #
    # Hours come from `TimeEntry.visible(viewer)` like everything else here, so
    # the page can only ever show time the viewer could already have found in
    # core. Capacity is not filtered: anybody who may open this page may open
    # the same person's timesheet and read it there.
    class Sheet
      attr_reader :query, :viewer

      delegate :span, :dates, :expanded_ids, to: :query

      def initialize(query:, viewer: User.current)
        @query = query
        @viewer = viewer
      end

      def rows
        @rows ||= sort(query.everyone? ? all_rows : all_rows.select(&:logged?))
      end

      def any?
        rows.any?
      end

      def people_count
        rows.size
      end

      # Everybody who logged something, whether or not their row survived the
      # scope filter — a headline that moved when you narrowed the list is a
      # number nobody could quote.
      def logged_count
        all_rows.count(&:logged?)
      end

      def daily_total(date)
        daily_totals[date] || 0.0
      end

      def daily_totals
        @daily_totals ||= dates.index_with { |date| rows.sum { |row| row.on(date) } }
      end

      def total
        @total ||= rows.sum(&:logged).round(2)
      end

      def capacity
        @capacity ||= rows.sum(&:capacity).round(2)
      end

      def expected
        @expected ||= rows.sum(&:expected).round(2)
      end

      def difference
        (total - expected).round(2)
      end

      def utilization
        return nil if capacity.zero?

        ((total / capacity) * 100).round
      end

      # Weekend or public holiday: the days nobody was asked to work. A personal
      # absence belongs to one person and cannot grey out a column shared by
      # everybody, so it is read on the row instead.
      def non_working?(date)
        calendar.non_working_reason(nil, date).present?
      end

      def truncated_users?
        candidates.limit(Query::MAX_USERS + 1).count > Query::MAX_USERS
      end

      def truncated_expansion?
        Array(query.expanded_ids).size >= Query::MAX_EXPANDED
      end

      private

      def sort(built)
        return built.sort_by(&:sort_key) unless query.by_hours?

        # Ties broken by name rather than left to the database, so reloading
        # the same page twice does not reorder it.
        built.sort_by { |row| [-row.logged, row.sort_key] }
      end

      def all_rows
        @all_rows ||= users.map { |user| row_for(user) }
      end

      def row_for(user)
        Row.new(user:,
                hours: dates.index_with { |date| logged.fetch([user.id, date], 0.0) },
                targets: dates.index_with { |date| calendar.hours_for(user.id, date) },
                capacity: calendar.total_for(user.id, dates),
                expected: calendar.total_for(user.id, elapsed_dates),
                details: details[user.id] || [])
      end

      # Only the days that have already happened. See Row for why.
      def elapsed_dates
        @elapsed_dates ||= dates.select { |date| date <= Time.zone.today }
      end

      def users
        @users ||= candidates.limit(Query::MAX_USERS).to_a
      end

      def user_ids
        @user_ids ||= users.map(&:id)
      end

      # Starts from the people, not from the time entries: with `scope=everyone`
      # the row worth seeing is the empty one, and a list built from the entries
      # could not contain it.
      def candidates
        scope = User.active.not_builtin.order(:lastname, :firstname, :id)
        scope = scope.where(id: query.user_ids) if query.user_ids.any?
        scope = scope.where(id: member_ids) if query.project_ids.any?
        scope = scope.where(id: viewer.id) unless viewer.allowed_in_any_project?(:view_time_entries)
        scope
      end

      def member_ids
        Member.where(project_id: query.project_ids).select(:user_id)
      end

      def calendar
        @calendar ||= CapacityCalendar.new(user_ids:, range: span.range)
      end

      # One query for every cell in the table.
      def logged
        @logged ||= filtered(TimeEntry.visible(viewer).where(user_id: user_ids, spent_on: span.range))
                      .group(:user_id, :spent_on)
                      .sum(:hours)
                      .transform_values(&:to_f)
      end

      # What each opened-up person actually worked on, in one query however
      # many of them are open.
      def details
        @details ||= begin
          ids = expanded_ids & user_ids
          ids.any? ? build_details(ids) : {}
        end
      end

      def build_details(ids)
        entries(ids).group_by(&:user_id).transform_values do |user_entries|
          user_entries.group_by { |entry| [entry.entity, entry.activity] }
                      .map { |(entity, activity), grouped| detail_row(entity, activity, grouped) }
                      .sort_by(&:sort_key)
        end
      end

      def detail_row(entity, activity, entries)
        row = Worklogs::Row.new(entity:, activity:)
        entries.group_by(&:spent_on).each do |date, day_entries|
          row.cells[date] = Worklogs::Cell.new(date:, entries: day_entries, row:)
        end
        row
      end

      def entries(ids)
        filtered(TimeEntry.visible(viewer).where(user_id: ids, spent_on: span.range))
          .includes(:activity, :project, entity: :project)
          .order(:spent_on, :id)
          .select { |entry| entry.entity.present? }
      end

      def filtered(scope)
        scope = scope.where(project_id: query.project_ids) if query.project_ids.any?
        scope = scope.where(activity_id: query.activity_ids) if query.activity_ids.any?
        scope
      end
    end
  end
end
