module Worklogs
  # Target hours per day for *many* users over one date range, loaded in four
  # queries no matter how many people are asked about.
  #
  # `Capacity` answers the same questions for a single user and a single week
  # and is built on this; a team-wide view over a quarter would otherwise run
  # two queries per person and one per week, which is how a page that looks
  # like a spreadsheet ends up taking eight seconds.
  #
  # Everything here reads core data — global working days, per-user working
  # hours (UserWorkingHours), holidays (NonWorkingDay) and personal absences
  # (UserNonWorkingTime). The plugin deliberately owns no schedule of its own.
  class CapacityCalendar
    NonWorkingReason = Struct.new(:kind, :label)

    attr_reader :range

    def initialize(user_ids:, range:)
      @user_ids = Array(user_ids).map(&:to_i).uniq
      @range = range
    end

    # Memoised because a team-wide page asks the same question about the same
    # day dozens of times — once per user row, and again for the totals.
    def hours_for(user_id, date)
      @hours ||= {}
      @hours[[user_id, date]] ||= compute_hours_for(user_id, date)
    end

    def total_for(user_id, dates)
      dates.sum { |date| hours_for(user_id, date) }
    end

    def working_days_for(user_id, dates)
      dates.select { |date| working_day?(user_id, date) }
    end

    def working_day?(user_id, date)
      non_working_reason(user_id, date).nil?
    end

    # nil when the day is a regular working day for this user, otherwise why
    # it is not.
    def non_working_reason(user_id, date)
      unless working_weekdays.include?(date.cwday)
        return NonWorkingReason.new(:weekend, I18n.t("worklogs.capacity.non_working_day"))
      end

      if (holiday = holidays[date])
        return NonWorkingReason.new(:holiday, holiday.name)
      end

      if absence_covering(user_id, date)
        return NonWorkingReason.new(:absence, I18n.t("worklogs.capacity.absence"))
      end

      nil
    end

    private

    def compute_hours_for(user_id, date)
      return 0.0 unless working_day?(user_id, date)

      schedule = schedule_for(user_id, date)
      hours = schedule ? schedule.public_send(:"#{weekday_name(date)}_hours") : default_hours
      hours.to_f
    end

    # What a working day is worth for somebody with no schedule of their own.
    # The plugin's setting first because core's is `format: :integer` and a
    # seven-and-a-half-hour day would be silently truncated there.
    def default_hours
      @default_hours ||= Settings.hours_per_day || Setting.hours_per_day
    end

    def working_weekdays
      @working_weekdays ||= Array(Setting.working_days).map(&:to_i)
    end

    def holidays
      @holidays ||= NonWorkingDay.where(date: range).index_by(&:date)
    end

    def absences
      @absences ||= UserNonWorkingTime
                      .where(user_id: @user_ids)
                      .where(start_date: ..range.last)
                      .where(end_date: range.first..)
                      .group_by(&:user_id)
    end

    def absence_covering(user_id, date)
      absences.fetch(user_id, EMPTY)
              .find { |absence| (absence.start_date..absence.end_date).cover?(date) }
    end

    # The working hours record in effect on `date`: the most recent one whose
    # valid_from is not in the future. A nil valid_from means "since forever".
    def schedule_for(user_id, date)
      schedules.fetch(user_id, EMPTY)
               .select { |schedule| schedule.valid_from.nil? || schedule.valid_from <= date }
               .max_by { |schedule| schedule.valid_from || Date.new(0) }
    end

    def schedules
      @schedules ||= UserWorkingHours.where(user_id: @user_ids).group_by(&:user_id)
    end

    def weekday_name(date)
      Date::DAYNAMES[date.wday].downcase
    end

    EMPTY = [].freeze
    private_constant :EMPTY
  end
end
