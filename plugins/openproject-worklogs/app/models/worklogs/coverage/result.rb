module Worklogs
  module Coverage
    # The coverage table: everyone who was expected to log time in the period,
    # what they logged, and where the gaps are.
    #
    # Logged hours come from `TimeEntry.visible(viewer)` like everything else in
    # this plugin — the page can only ever accuse somebody of a gap the viewer
    # was allowed to see in the first place. Capacity is not filtered, because
    # anybody who may open this page may already open the same person's
    # timesheet and read it there.
    class Result
      MAX_USERS = 200
      MAX_BUCKETS = 60

      attr_reader :query, :viewer

      def initialize(query:, viewer:)
        @query = query
        @viewer = viewer
      end

      def buckets
        @buckets ||= Bucket.build(query).first(MAX_BUCKETS)
      end

      def rows
        @rows ||= build_rows
      end

      def users
        @users ||= candidates.limit(MAX_USERS + 1).to_a
      end

      def truncated_users?
        users.size > MAX_USERS
      end

      def truncated_buckets?
        Bucket.build(query).size > MAX_BUCKETS
      end

      def any?
        rows.any?
      end

      # The totals row is the whole candidate set, not only the rows left after
      # filtering to "missing" — a team utilisation that changed when you
      # narrowed the list would be a number nobody could quote.
      def totals
        @totals ||= Row.new(user: nil, cells: total_cells)
      end

      def missing_count
        all_rows.count(&:missing?)
      end

      # The sum of what individuals are short, not the team's net position.
      # One person logging overtime does not fill in somebody else's empty
      # Thursday, and a headline that says it does is the wrong headline.
      def missing_hours
        all_rows.sum(&:missing).round(2)
      end

      # Per column, on the same rule: gaps added up, never netted off against
      # somebody else's overtime.
      def missing_by_bucket
        @missing_by_bucket ||= buckets.each_index.map do |index|
          all_rows.sum { |row| row.cells[index].missing }.round(2)
        end
      end

      def silent_count
        all_rows.count(&:silent?)
      end

      def complete_count
        all_rows.count(&:complete?)
      end

      def calendar
        @calendar ||= CapacityCalendar.new(user_ids: user_ids, range: query.range)
      end

      private

      def user_ids
        @user_ids ||= users.first(MAX_USERS).map(&:id)
      end

      def build_rows
        selected = all_rows
        selected = selected.select(&:missing?) if query.missing_only?
        selected = selected.select(&:complete?) if query.complete_only?
        selected
      end

      def all_rows
        @all_rows ||= users.first(MAX_USERS).map { |user| row_for(user) }
      end

      def row_for(user)
        cells = buckets.map do |bucket|
          Cell.new(bucket:,
                   logged: logged_for(user.id, bucket),
                   capacity: calendar.total_for(user.id, bucket.dates),
                   expected: calendar.total_for(user.id, bucket.elapsed_dates),
                   submission: submission_for(user.id, bucket))
        end

        Row.new(user:, cells:)
      end

      def total_cells
        buckets.each_with_index.map do |bucket, index|
          column = all_rows.map { |row| row.cells[index] }

          Cell.new(bucket:,
                   logged: column.sum(&:logged),
                   capacity: column.sum(&:capacity),
                   expected: column.sum(&:expected))
        end
      end

      def logged_for(user_id, bucket)
        bucket.dates.sum { |date| logged.fetch([user_id, date], 0.0) }
      end

      # One query for the whole table. Grouping by day rather than by bucket
      # keeps the SQL free of any knowledge of what a week is, which is a
      # setting and not a constant.
      def logged
        @logged ||= TimeEntry.visible(viewer)
                             .where(user_id: user_ids, spent_on: query.range)
                             .group(:user_id, :spent_on)
                             .sum(:hours)
                             .transform_values { |hours| hours.to_f }
      end

      # Only meaningful for whole weeks; a day or a month column has no single
      # submission behind it.
      def submissions
        @submissions ||= if query.group_by == "week"
                           Submission.where(user_id: user_ids, period_start: query.range)
                                     .index_by { |submission| [submission.user_id, submission.period_start] }
                         else
                           {}
                         end
      end

      def submission_for(user_id, bucket)
        submissions[[user_id, bucket.start_date]]
      end

      # Everybody who could be expected to log time, not only everybody who
      # did. A page about missing time that starts from the time entries would
      # never show the person who logged nothing at all — the one case it
      # exists for.
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
    end
  end
end
