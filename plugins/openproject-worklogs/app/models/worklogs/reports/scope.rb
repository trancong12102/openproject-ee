module Worklogs
  module Reports
    # The set of time entries a report covers.
    #
    # Built on `TimeEntry.visible(viewer)`, which is core's own permission
    # scope — view_time_entries per project, or view_own_time_entries on your
    # own entries. The plugin narrows that set and never widens it, so a report
    # cannot show a row the viewer could not have found in core.
    class Scope
      attr_reader :query, :viewer

      def initialize(query:, viewer: User.current)
        @query = query
        @viewer = viewer
      end

      def relation
        @relation ||= begin
          scope = TimeEntry.visible(viewer).where(spent_on: query.range)
          scope = join_work_packages(scope) if work_package_join?
          apply_filters(scope)
        end
      end

      # Narrows to one cell of the pivot: the dimension values that led to it.
      # Used by the drill-down, so the list behind a number is the number.
      def where_dimensions(pairs)
        pairs.reduce(needs_join_for(pairs) ? join_work_packages(relation) : relation) do |scope, (dimension, value)|
          if value.nil? || value == ""
            scope.where("#{dimension.expression} IS NULL")
          else
            scope.where("#{dimension.expression} = ?", value)
          end
        end
      end

      def costs_visible?
        @costs_visible ||= viewer.allowed_in_any_project?(:view_hourly_rates) ||
          viewer.allowed_in_any_project?(:view_own_hourly_rate)
      end

      private

      def work_package_join?
        query.dimensions.any?(&:requires_work_package_join?) ||
          query.type_ids.any? || query.status_ids.any?
      end

      def needs_join_for(pairs)
        !work_package_join? && pairs.any? { |dimension, _| dimension.requires_work_package_join? }
      end

      # A left join, not an inner one: time logged on a meeting is still time,
      # and dropping it would make the report disagree with the timesheet.
      def join_work_packages(scope)
        scope.joins(<<~SQL.squish)
          LEFT JOIN work_packages
            ON work_packages.id = time_entries.entity_id
           AND time_entries.entity_type = 'WorkPackage'
        SQL
      end

      def apply_filters(scope)
        scope = scope.where(user_id: query.user_ids) if query.user_ids.any?
        scope = scope.where(project_id: query.project_ids) if query.project_ids.any?
        scope = scope.where(activity_id: query.activity_ids) if query.activity_ids.any?
        scope = scope.where(work_packages: { type_id: query.type_ids }) if query.type_ids.any?
        scope = scope.where(work_packages: { status_id: query.status_ids }) if query.status_ids.any?
        scope
      end
    end
  end
end
