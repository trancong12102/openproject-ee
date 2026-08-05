module Worklogs
  # Answers "may this viewer do X to this timesheet" using core's time entry
  # permissions only. The plugin adds no way to see or change time that core
  # would refuse — view_worklogs is an entry ticket, not an override.
  class Policy
    attr_reader :viewer, :subject

    def initialize(viewer:, subject:)
      @viewer = viewer
      @subject = subject
    end

    def own?
      viewer == subject
    end

    def may_view?
      own? || viewer.allowed_in_any_project?(:view_time_entries)
    end

    def may_edit?(time_entry)
      time_entry.editable_by?(viewer)
    end

    def may_destroy?(time_entry)
      may_edit?(time_entry)
    end

    # Whether the viewer may add time on `entity` for `subject`.
    def may_log?(entity)
      project = entity.project
      return false if project.nil?

      if own?
        entity.is_a?(WorkPackage) && viewer.allowed_in_work_package?(:log_own_time, entity)
      else
        viewer.allowed_in_project?(:log_time, project)
      end
    end
  end
end
