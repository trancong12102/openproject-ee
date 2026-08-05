module Worklogs
  # A calendar month, as a timesheet covers it.
  #
  # Deliberately the same shape as `Week` — start, end, dates, previous, next —
  # because everything above it takes one or the other and never asks which:
  # the grid draws a column per date, capacity is asked per date, and totals
  # are sums. Only the things that are genuinely weekly (submitting, pinned
  # rows) reach through `#weeks`.
  class Month
    attr_reader :start_date

    class << self
      def containing(date)
        new(date.to_date.beginning_of_month)
      end

      def current
        containing(Time.zone.today)
      end

      # Accepts an ISO-8601 date, the "2026-08" a month input sends, "today",
      # or nothing.
      def from_param(param)
        return current if param.blank? || param == "today"

        text = param.to_s
        containing(Date.iso8601(text.match?(/\A\d{4}-\d{2}\z/) ? "#{text}-01" : text))
      rescue Date::Error
        current
      end
    end

    def initialize(start_date)
      @start_date = start_date.beginning_of_month
    end

    def kind = "month"
    def week? = false
    def month? = true

    def end_date
      start_date.end_of_month
    end

    def range
      start_date..end_date
    end

    def dates
      range.to_a
    end

    def length
      dates.size
    end

    def previous
      self.class.new(start_date << 1)
    end

    def next
      self.class.new(start_date >> 1)
    end

    def include?(date)
      range.cover?(date)
    end

    def current?
      include?(Time.zone.today)
    end

    # Every week that has a day in this month, including the two that spill
    # over its ends. A submission covers a whole week or none of it, so a month
    # view that only listed the weeks wholly inside it would be silent about
    # the first and last few days it is showing.
    def weeks
      @weeks ||= begin
        first = Week.containing(start_date)
        weeks = [first]
        weeks << weeks.last.next while weeks.last.end_date < end_date
        weeks
      end
    end

    def to_param
      start_date.iso8601
    end

    def to_params
      { date: to_param, span: kind }
    end

    def ==(other)
      other.is_a?(Month) && other.start_date == start_date
    end
    alias eql? ==

    def hash
      [self.class, start_date].hash
    end
  end
end
