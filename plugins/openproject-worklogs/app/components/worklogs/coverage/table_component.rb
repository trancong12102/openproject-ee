module Worklogs
  module Coverage
    # One row per person, one column per week (or day, or month), plus what the
    # period as a whole came to.
    #
    # Every cell is a link into that person's timesheet for that bucket. A page
    # that tells you somebody is four hours short and then makes you go and find
    # them yourself has done half a job.
    class TableComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::CoverageHelper
      include OpPrimer::ComponentHelpers

      options :result

      delegate :query, :buckets, :rows, :totals, to: :result

      def any?
        rows.any?
      end

      # The sum of the column above it, not the team's net position. A totals
      # row that does not add up is worse than no totals row.
      def total_missing
        result.missing_hours
      end

      def bucket_label(bucket)
        bucket.short_label(query.group_by)
      end

      def bucket_title(bucket)
        bucket.label(query.group_by)
      end

      def bucket_classes(bucket)
        classes = ["worklogs-coverage--bucket"]
        classes << "-current" if bucket.current?
        classes << "-future" if bucket.future?
        classes
      end

      def cell_classes(cell)
        ["worklogs-coverage--cell", "-#{cell.state}"]
      end

      def cell_value(cell)
        return "" if cell.state == :off || (cell.state == :future && cell.empty?)

        worklogs_duration(cell.logged)
      end

      # The shortfall, and only the shortfall. A grid that also wrote "+2h" on
      # every over-logged cell would be a grid where the four cells that matter
      # no longer stand out.
      def cell_note(cell)
        return nil unless cell.missing?

        "−#{worklogs_duration(cell.missing)}"
      end

      def cell_title(cell, row)
        parts = ["#{row.user.name} · #{bucket_title(cell.bucket)}",
                 I18n.t("worklogs.coverage.cell_title",
                        logged: worklogs_duration(cell.logged),
                        expected: worklogs_duration(cell.expected))]
        parts << cell.submission.status_label if cell.submission
        parts.join(" — ")
      end

      # A day column has no timesheet of its own, so it lands on the week that
      # contains it with that day in view.
      def cell_href(cell, row)
        worklogs_root_path(date: cell.bucket.start_date.iso8601, user_id: row.user.id)
      end

      def user_href(row)
        worklogs_root_path(date: query.from.iso8601, user_id: row.user.id)
      end

      def row_classes(row)
        classes = ["worklogs-coverage--row"]
        classes << "-silent" if row.silent?
        classes
      end

      def utilization_classes(value)
        classes = ["worklogs-coverage--utilization"]
        classes << if value.nil? then "-none"
                   elsif value >= 100 then "-ok"
                   elsif value >= 90 then "-short"
                   else "-bad"
                   end
        classes
      end

      # Approved weeks are worth a mark: a gap in a week somebody already signed
      # off is a different conversation from a gap in a week still being filled.
      def submission_mark(cell)
        return nil if cell.submission.nil?

        case cell.submission.status
        when "approved" then "✓"
        when "submitted" then "⏳"
        else nil
        end
      end

      def notes
        notes = []
        notes << I18n.t("worklogs.coverage.truncated_users", count: Result::MAX_USERS) if result.truncated_users?
        notes << I18n.t("worklogs.coverage.truncated_buckets", count: Result::MAX_BUCKETS) if result.truncated_buckets?
        notes
      end

      def blank_description
        return I18n.t("worklogs.coverage.blank_filtered") if query.missing_only? || query.complete_only?

        I18n.t("worklogs.coverage.blank_description")
      end
    end
  end
end
