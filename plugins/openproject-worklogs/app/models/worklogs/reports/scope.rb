module Worklogs
  module Reports
    # The set of time entries a report covers.
    #
    # Built on `TimeEntry.visible(viewer)`, which is core's own permission
    # scope — view_time_entries per project, or view_own_time_entries on your
    # own entries. The plugin narrows that set and never widens it, so a report
    # cannot show a row the viewer could not have found in core.
    class Scope
      # The id no user has, so "nobody" can travel in the same list of ids as
      # everybody else.
      UNASSIGNED = 0

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
        query.dimensions.any?(&:requires_work_package_join?) || query.work_package_filters?
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
        scope = apply_entry_filters(scope)
        scope = apply_work_package_filters(scope)
        apply_text(scope)
      end

      def apply_entry_filters(scope)
        scope = scope.where(user_id: query.user_ids) if query.user_ids.any?
        scope = scope.where(project_id: query.project_ids) if query.project_ids.any?
        scope = scope.where(activity_id: query.activity_ids) if query.activity_ids.any?
        # The work package filter is deliberately on the time entry rather than
        # on the joined row: it has to hold whether or not anything else asked
        # for the join, and time logged on a meeting is not this work package.
        if query.work_package_ids.any?
          scope = scope.where(entity_type: "WorkPackage", entity_id: query.work_package_ids)
        end
        scope
      end

      def apply_work_package_filters(scope)
        scope = scope.where(work_packages: { type_id: query.type_ids }) if query.type_ids.any?
        scope = scope.where(work_packages: { status_id: query.status_ids }) if query.status_ids.any?
        scope = scope.where(work_packages: { priority_id: query.priority_ids }) if query.priority_ids.any?
        scope = scope.where(work_packages: { version_id: query.version_ids }) if query.version_ids.any?
        apply_assignee(scope)
      end

      # "Nobody" is a legitimate answer to "assigned to whom", and the picker
      # offers it under the id nobody has.
      #
      # It has to say so about a work package that has no assignee, not about a
      # time entry that has no work package: without the entity guard, an hour
      # logged on a meeting would answer to every "unassigned" report, because
      # the left join left its assignee null too.
      def apply_assignee(scope)
        return scope if query.assignee_ids.empty?

        ids = query.assignee_ids - [UNASSIGNED]
        return scope.where(work_packages: { assigned_to_id: ids }) unless
          query.assignee_ids.include?(UNASSIGNED)

        none = scope.where(entity_type: "WorkPackage").where(work_packages: { assigned_to_id: nil })
        return none if ids.empty?

        none.or(scope.where(work_packages: { assigned_to_id: ids }))
      end

      # Matches the entry's own comment, which is what somebody looking for
      # "invoice" or a ticket reference they typed while logging means. Case
      # insensitive, and the wildcards in what was typed are escaped so a
      # comment containing a literal % can still be searched for.
      def apply_text(scope)
        return scope if query.text.blank?

        scope.where("time_entries.comments ILIKE ?", "%#{sanitize_like(query.text)}%")
      end

      def sanitize_like(text)
        ActiveRecord::Base.sanitize_sql_like(text)
      end
    end
  end
end
