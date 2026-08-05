module Worklogs
  # Target hours per day for one user over one span — a week or a month — so
  # the grid can show "38.5 / 40" and flag under-/over-logged days.
  #
  # A thin view onto `CapacityCalendar`, which does the loading. One user and
  # one span is the common case and deserves the shorter call; it is not a
  # second implementation of what a working day is.
  class Capacity
    NonWorkingReason = CapacityCalendar::NonWorkingReason

    def initialize(user:, span:, calendar: nil)
      @user = user
      @span = span
      @calendar = calendar || CapacityCalendar.new(user_ids: [user.id], range: span.range)
    end

    # Target hours for the given date. 0 on weekends, holidays and absences.
    def hours_for(date)
      @calendar.hours_for(@user.id, date)
    end

    def total
      @calendar.total_for(@user.id, @span.dates)
    end

    # What the user was supposed to have logged by now. Comparing a Tuesday
    # against the whole week's capacity would report everyone as nine hours
    # behind, every Tuesday, which is noise rather than information — and on a
    # month, against a month's worth.
    def expected_so_far(today = Time.zone.today)
      return 0.0 if today < @span.start_date
      return total if today > @span.end_date

      @calendar.total_for(@user.id, @span.dates.take_while { |date| date <= today })
    end

    def working_days
      @calendar.working_days_for(@user.id, @span.dates)
    end

    def working_day?(date)
      @calendar.working_day?(@user.id, date)
    end

    # nil when the day is a regular working day, otherwise why it is not.
    def non_working_reason(date)
      @calendar.non_working_reason(@user.id, date)
    end
  end
end
