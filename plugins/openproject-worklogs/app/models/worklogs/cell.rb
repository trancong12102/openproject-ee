module Worklogs
  # One (row, day) intersection of the grid. Usually holds zero or one time
  # entry; more than one happens when the same work package + activity was
  # logged several times in a day (different comments or start times), in which
  # case the cell shows the sum and defers editing to the day detail dialog.
  class Cell
    attr_reader :date, :entries, :row

    def initialize(date:, entries: [], row: nil)
      @date = date
      @entries = entries
      @row = row
    end

    def hours
      entries.sum { |entry| entry.hours_for_calculation.to_f }
    end

    def empty?
      entries.empty?
    end

    def split?
      entries.size > 1
    end

    def entry
      entries.first unless split?
    end

    def ongoing?
      entries.any?(&:ongoing?)
    end

    def comments
      entries.filter_map { |entry| entry.comments.presence }
    end

    def id
      entry&.id
    end
  end
end
