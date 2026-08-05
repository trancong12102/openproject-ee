module Worklogs
  # Target hours per day for one user over one week, so the grid can show
  # "38.5 / 40" and flag under-/over-logged days.
  #
  # Everything here reads core data — global working days, per-user working
  # hours (UserWorkingHours), holidays (NonWorkingDay) and personal absences
  # (UserNonWorkingTime). The plugin deliberately owns no schedule of its own.
  class Capacity
    NonWorkingReason = Struct.new(:kind, :label)

    def initialize(user:, week:)
      @user = user
      @week = week
    end

    # Target hours for the given date. 0 on weekends, holidays and absences.
    def hours_for(date)
      return 0.0 unless working_day?(date)

      schedule = schedule_for(date)
      hours = schedule ? schedule.public_send(:"#{weekday_name(date)}_hours") : Setting.hours_per_day
      hours.to_f
    end

    def total
      @week.dates.sum { |date| hours_for(date) }
    end

    # What the user was supposed to have logged by now. Comparing a Tuesday
    # against the whole week's capacity would report everyone as nine hours
    # behind, every Tuesday, which is noise rather than information.
    def expected_so_far(today = Time.zone.today)
      return 0.0 if today < @week.start_date
      return total if today > @week.end_date

      @week.dates.take_while { |date| date <= today }.sum { |date| hours_for(date) }
    end

    def working_days
      @week.dates.select { |date| working_day?(date) }
    end

    def working_day?(date)
      non_working_reason(date).nil?
    end

    # nil when the day is a regular working day, otherwise why it is not.
    def non_working_reason(date)
      unless working_weekdays.include?(date.cwday)
        return NonWorkingReason.new(:weekend, I18n.t("worklogs.capacity.non_working_day"))
      end

      if (holiday = holidays[date])
        return NonWorkingReason.new(:holiday, holiday.name)
      end

      if absence_covering(date)
        return NonWorkingReason.new(:absence, I18n.t("worklogs.capacity.absence"))
      end

      nil
    end

    private

    def working_weekdays
      @working_weekdays ||= Array(Setting.working_days).map(&:to_i)
    end

    def holidays
      @holidays ||= NonWorkingDay.where(date: @week.range).index_by(&:date)
    end

    def absences
      @absences ||= UserNonWorkingTime
                      .where(user_id: @user.id)
                      .where(start_date: ..@week.end_date)
                      .where(end_date: @week.start_date..)
                      .to_a
    end

    def absence_covering(date)
      absences.find { |absence| (absence.start_date..absence.end_date).cover?(date) }
    end

    # The working hours record in effect on `date`: the most recent one whose
    # valid_from is not in the future. A nil valid_from means "since forever".
    def schedule_for(date)
      schedules
        .select { |schedule| schedule.valid_from.nil? || schedule.valid_from <= date }
        .max_by { |schedule| schedule.valid_from || Date.new(0) }
    end

    def schedules
      @schedules ||= UserWorkingHours.where(user_id: @user.id).to_a
    end

    def weekday_name(date)
      Date::DAYNAMES[date.wday].downcase
    end
  end
end
