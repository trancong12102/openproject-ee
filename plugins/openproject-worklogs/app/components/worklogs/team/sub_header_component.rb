module Worklogs
  module Team
    # Which span the team sheet is showing, the two arrows either side of it,
    # and the way out to a spreadsheet.
    class SubHeaderComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include Worklogs::TeamHelper

      options :query

      delegate :span, to: :query

      def title
        worklogs_span_title(span)
      end

      def previous_attrs
        { href: worklogs_team_href(query.with_span(span.previous)),
          aria: { label: I18n.t("worklogs.timesheet.previous_span") } }
      end

      def next_attrs
        { href: worklogs_team_href(query.with_span(span.next)),
          aria: { label: I18n.t("worklogs.timesheet.next_span") } }
      end

      def today_href
        worklogs_team_href(query, date: "today")
      end

      def export_href(format)
        worklogs_team_path(worklogs_team_params(query).merge(format:))
      end
    end
  end
end
