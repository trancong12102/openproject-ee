module Worklogs
  # The period a timesheet covers. Week boundaries follow the instance's
  # start_of_week setting, so the grid lines up with core's my/time_tracking.
  class Week
    LENGTH = 7

    attr_reader :start_date

    class << self
      def start_day
        case Setting.start_of_week
        when 6 then :saturday
        when 7 then :sunday
        else :monday
        end
      end

      def containing(date)
        new(date.to_date.beginning_of_week(start_day))
      end

      def current
        containing(Time.zone.today)
      end

      # Accepts the `date` query parameter in ISO-8601 form, "today", or nothing.
      def from_param(param)
        return current if param.blank? || param == "today"

        containing(Date.iso8601(param))
      rescue Date::Error
        current
      end
    end

    def initialize(start_date)
      @start_date = start_date
    end

    def end_date
      start_date + (LENGTH - 1)
    end

    def range
      start_date..end_date
    end

    def dates
      range.to_a
    end

    def previous
      self.class.new(start_date - LENGTH)
    end

    def next
      self.class.new(start_date + LENGTH)
    end

    def include?(date)
      range.cover?(date)
    end

    def current?
      include?(Time.zone.today)
    end

    def to_param
      start_date.iso8601
    end

    def ==(other)
      other.is_a?(Week) && other.start_date == start_date
    end
    alias eql? ==

    def hash
      start_date.hash
    end
  end
end
