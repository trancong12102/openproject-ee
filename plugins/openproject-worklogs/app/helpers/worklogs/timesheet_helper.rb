module Worklogs
  module TimesheetHelper
    # Hours are always rendered with a dot separator and no trailing zeros:
    # 8.0 -> "8", 7.5 -> "7.5", 1.25 -> "1.25". Time trackers are read as
    # numbers far more often than as prose, and a locale-swapped separator here
    # would fight the parser that accepts "1h30" / "1,5" / "90m" on input.
    def worklogs_hours(value)
      return "" if value.nil?

      rounded = value.to_f.round(2)
      return "" if rounded.zero?

      format("%g", rounded)
    end

    # Blank reads as "nothing here" inside the grid, but a headline figure has
    # to say zero out loud.
    def worklogs_hours_figure(value)
      worklogs_hours(value).presence || "0"
    end

    def worklogs_hours_with_unit(value)
      hours = worklogs_hours(value)
      hours.presence ? "#{hours}h" : "–"
    end

    def worklogs_week_range(week)
      start_date = week.start_date
      end_date = week.end_date

      if start_date.month == end_date.month
        "#{start_date.day} – #{I18n.l(end_date, format: :long)}"
      else
        "#{I18n.l(start_date, format: :long)} – #{I18n.l(end_date, format: :long)}"
      end
    end

    def worklogs_day_name(date)
      I18n.t("date.abbr_day_names")[date.wday]
    end
  end
end
