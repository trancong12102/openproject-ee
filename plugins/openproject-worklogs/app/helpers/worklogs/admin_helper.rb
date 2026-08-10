module Worklogs
  module AdminHelper
    # Day names in the instance's own order, so an instance whose week starts on
    # Sunday does not offer Monday first.
    def weekday_options
      start = Worklogs::Week.start_day
      offset = Date::DAYNAMES.index(start.to_s.capitalize)

      (0..6).map do |index|
        date = Date.new(2024, 1, 1) + ((offset + index - 1) % 7)
        [I18n.l(date, format: "%A"), date.cwday]
      end
    end

    def hour_options
      (0..23).map { |hour| [format("%02d:00", hour), hour] }
    end

    # Core's working weekdays, written out in the instance's own week order so
    # the sentence reads the way the calendar looks.
    def working_weekday_names
      working = Array(Setting.working_days).map(&:to_i)

      weekday_options.map(&:last)
                     .select { |cwday| working.include?(cwday) }
                     .map { |cwday| I18n.l(Date.commercial(2024, 1, cwday), format: "%A") }
                     .join(", ")
    end
  end
end
