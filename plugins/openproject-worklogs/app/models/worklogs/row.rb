module Worklogs
  # A grid row: one entity (work package or meeting) logged under one activity.
  #
  # Splitting by activity as well as entity is deliberate — logging 2h of
  # "Development" and 1h of "Testing" on the same work package are two different
  # facts, and merging them into one row would make the cell uneditable.
  class Row
    attr_reader :entity, :activity, :cells

    # Stable identifier used as the DOM id and in the cell update payload.
    def self.key_for(entity, activity)
      [entity.class.name, entity.id, activity&.id || "none"].join("-")
    end

    def initialize(entity:, activity:, cells: {})
      @entity = entity
      @activity = activity
      @cells = cells
    end

    def key
      @key ||= self.class.key_for(entity, activity)
    end

    def project
      entity.project
    end

    def cell(date)
      cells[date] ||= Cell.new(date:, row: self)
    end

    def total
      cells.values.sum(&:hours)
    end

    def empty?
      cells.values.all?(&:empty?)
    end

    def work_package?
      entity.is_a?(WorkPackage)
    end

    def subject
      entity.respond_to?(:subject) ? entity.subject : entity.title
    end

    # "#1481" for work packages, the project identifier prefix is shown separately.
    def reference
      work_package? ? "##{entity.id}" : nil
    end

    def sort_key
      [project&.name.to_s, subject.to_s, activity&.position || 0]
    end
  end
end
