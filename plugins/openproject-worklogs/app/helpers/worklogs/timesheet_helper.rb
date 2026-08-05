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

    # Headline figures use OpenProject's own duration wording ("30h 15m") so the
    # page reads like the rest of the product. The grid itself stays decimal:
    # its cells are inputs, and you should see the number you typed.
    def worklogs_duration(value)
      DurationConverter.output(value.to_f.round(2), format: :hours_and_minutes).presence || "0h"
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

    # What the sheet says it is showing. A week is a number and a range,
    # because "Week 32" alone tells nobody which days; a month is its own name.
    def worklogs_span_title(span)
      return I18n.l(span.start_date, format: "%B %Y") if span.month?

      "#{I18n.t('worklogs.timesheet.week_number', number: span.start_date.cweek)} · #{worklogs_week_range(span)}"
    end

    # Everything that identifies the sheet you are looking at: which span,
    # whose, filtered how. Every link on the page is this hash with one thing
    # changed, which is what keeps the filters alive across a week step.
    def worklogs_timesheet_params(timesheet, overrides = {})
      timesheet.span.to_params
               .merge(user_id: timesheet.user.id,
                      project_ids: timesheet.project_ids,
                      activity_ids: timesheet.activity_ids)
               .compact_blank
               .merge(overrides.symbolize_keys)
               .compact
    end

    def worklogs_timesheet_href(timesheet, overrides = {})
      worklogs_root_path(worklogs_timesheet_params(timesheet, overrides))
    end

    def worklogs_grid_href(timesheet, overrides = {})
      worklogs_grid_path(worklogs_timesheet_params(timesheet, overrides))
    end

    # Each dropdown is its own GET form, so it has to carry the rest of the
    # sheet with it or applying one filter would reset every other.
    def worklogs_timesheet_hidden_fields(timesheet, except: [])
      excluded = Array(except).map(&:to_sym)

      safe_join(worklogs_timesheet_params(timesheet).except(*excluded).flat_map do |name, value|
        Array(value).map do |single|
          hidden_field_tag("#{name}#{'[]' if value.is_a?(Array)}", single, id: nil)
        end
      end)
    end
  end
end
