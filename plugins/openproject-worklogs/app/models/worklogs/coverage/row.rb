module Worklogs
  module Coverage
    # One person across the whole period.
    class Row
      attr_reader :user, :cells

      def initialize(user:, cells:)
        @user = user
        @cells = cells
      end

      def logged
        @logged ||= cells.sum(&:logged).round(2)
      end

      def capacity
        @capacity ||= cells.sum(&:capacity).round(2)
      end

      def expected
        @expected ||= cells.sum(&:expected).round(2)
      end

      def difference
        (logged - expected).round(2)
      end

      # The sum of the gaps, not the net position. Somebody who logged nothing
      # one week and twelve hours of overtime the next has an empty week to
      # explain, and a row saying "0 missing" would hide exactly the thing this
      # page exists to surface. It also keeps the column adding up: every row
      # is the sum of its cells, and the footer the sum of its rows.
      def missing
        @missing ||= cells.sum(&:missing).round(2)
      end

      def utilization
        return nil if expected.zero?

        ((logged / expected) * 100).round
      end

      def missing_buckets
        cells.count(&:missing?)
      end

      def missing?
        missing_buckets.positive?
      end

      def complete?
        !missing? && expected.positive?
      end

      # Nothing at all, anywhere in the period. Worth its own state: it usually
      # means somebody left, joined, or never got told to log time — not that
      # they had a bad month.
      def silent?
        logged.zero? && expected.positive?
      end
    end
  end
end
