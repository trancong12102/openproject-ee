module Worklogs
  module Team
    # The team grid: one line per person, one column per day, and — for anyone
    # opened up — their work packages underneath.
    #
    # Read-only on purpose. Editing somebody else's hours from a list of forty
    # people is a way to get it wrong quietly; every figure here is a link into
    # the sheet where that time can be seen in full and changed deliberately.
    class TableComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include Worklogs::TeamHelper

      options :sheet, :query

      delegate :span, :dates, :rows, :any?, :daily_total, :total, :expected,
               :difference, :utilization, :truncated_users?, to: :sheet

      def month?
        span.month?
      end

      def week_start?(date)
        month? && date != dates.first && date == date.beginning_of_week(Week.start_day)
      end

      def week_tag(date)
        "W#{date.cweek}"
      end

      def today?(date)
        date == Time.zone.today
      end

      def column_classes(date)
        classes = ["worklogs-team--day"]
        classes << "-today" if today?(date)
        classes << "-non-working" if sheet.non_working?(date)
        classes << "-week-start" if week_start?(date)
        classes
      end

      def cell_classes(row, date)
        classes = column_classes(date) - ["worklogs-team--day"]
        classes.unshift("worklogs-team--cell")
        classes << "-off" if row.off?(date)
        classes << "-gap" if row.gap?(date)
        classes
      end

      def detail_cell_classes(date)
        (column_classes(date) - ["worklogs-team--day"]).unshift("worklogs-team--cell", "-detail")
      end

      def expanded?(row)
        query.expanded?(row.user)
      end

      # Opening a person up is a link, so it lands in the URL with everything
      # else and can be sent to somebody as "look at this".
      def toggle_href(row)
        worklogs_team_href(query.toggling(row.user))
      end

      def toggle_label(row)
        I18n.t(expanded?(row) ? "worklogs.team.collapse" : "worklogs.team.expand", name: row.user.name)
      end

      # Their own sheet, in the same span and under the same filters: the page
      # you would have had to go and find by hand.
      def person_href(row)
        worklogs_root_path(span.to_params.merge(user_id: row.user.id,
                                                project_ids: query.project_ids,
                                                activity_ids: query.activity_ids).compact_blank)
      end

      # A cell points at the week that day is in, whatever the sheet is showing.
      # From a month, "what did they do on the 14th" is a question about a week.
      def cell_href(row, date)
        worklogs_root_path({ date: date.iso8601,
                             user_id: row.user.id,
                             project_ids: query.project_ids,
                             activity_ids: query.activity_ids }.compact_blank)
      end

      def cell_title(row, date)
        return I18n.t("worklogs.team.day_off", name: row.user.name) if row.off?(date)

        "#{row.user.name} · #{I18n.l(date, format: :long)}"
      end

      def row_difference_label(row)
        return "±0" if row.difference.zero?

        "#{row.difference.positive? ? '+' : '−'}#{worklogs_hours(row.difference.abs)}"
      end

      def difference_scheme(value)
        return "-over" if value.positive?
        return "-under" if value.negative?

        "-level"
      end

      def utilization_label(value)
        return "–" if value.nil?

        "#{value}%"
      end

      def detail_label(detail)
        [detail.reference, detail.subject].compact.join(" ")
      end

      def detail_href(detail)
        return nil unless detail.work_package?

        work_package_path(detail.entity)
      end

      def notes
        notes = []
        notes << I18n.t("worklogs.team.truncated_users", count: Query::MAX_USERS) if truncated_users?
        if sheet.truncated_expansion?
          notes << I18n.t("worklogs.team.truncated_expansion", count: Query::MAX_EXPANDED)
        end
        notes
      end

      def blank_description
        I18n.t(query.everyone? ? "worklogs.team.blank_description" : "worklogs.team.blank_description_logged")
      end
    end
  end
end
