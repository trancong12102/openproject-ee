module Worklogs
  module Coverage
    # The four numbers somebody opens this page to find out.
    class SummaryComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::CoverageHelper
      include OpPrimer::ComponentHelpers

      options :result

      delegate :query, :totals, to: :result

      def people
        result.rows.size
      end

      def missing_count
        result.missing_count
      end

      def silent_count
        result.silent_count
      end

      def complete_count
        result.complete_count
      end

      def total_people
        missing_count + complete_count + neither_count
      end

      def logged
        worklogs_duration(totals.logged)
      end

      def expected
        worklogs_duration(totals.expected)
      end

      def missing_hours
        worklogs_duration(result.missing_hours)
      end

      def utilization
        worklogs_utilization(totals.utilization)
      end

      # Green at or above target, amber when short, red when badly short.
      # Three states, because "83%" on its own is a number nobody acts on.
      def utilization_scheme
        value = totals.utilization
        return "-none" if value.nil?
        return "-ok" if value >= 100
        return "-short" if value >= 90

        "-bad"
      end

      def missing_scheme
        missing_count.zero? ? "-ok" : "-short"
      end

      def silent_scheme
        silent_count.zero? ? "-ok" : "-bad"
      end

      def missing_href
        worklogs_coverage_href(query, scope: "missing")
      end

      private

      # People with capacity who are neither complete nor short do not exist —
      # but people with *no* capacity in the period do, and they belong in
      # neither bucket.
      def neither_count
        result.rows.count { |row| row.expected.zero? }
      end
    end
  end
end
