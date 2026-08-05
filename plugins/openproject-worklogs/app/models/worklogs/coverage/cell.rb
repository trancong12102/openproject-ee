module Worklogs
  module Coverage
    # One person, one bucket: what they logged against what they owed.
    class Cell
      attr_reader :bucket, :logged, :capacity, :expected, :submission

      def initialize(bucket:, logged:, capacity:, expected:, submission: nil)
        @bucket = bucket
        @logged = logged.round(2)
        @capacity = capacity.round(2)
        @expected = expected.round(2)
        @submission = submission
      end

      # Against `expected`, not `capacity`: on a Tuesday the whole week is not
      # yet owed, and reporting everyone as 24h short every Tuesday is noise
      # rather than information.
      def difference
        (logged - expected).round(2)
      end

      def missing
        [-difference, 0].max.round(2)
      end

      def missing?
        state == :short
      end

      # Time logged ahead of the day it was due is still time logged; a bucket
      # only reads as "not yet" while there is genuinely nothing in it.
      def state
        return :off if capacity.zero?
        return :future if logged.zero? && bucket.future?
        return :met if difference >= 0

        :short
      end

      # Of what has been owed so far. A bucket nobody owes anything in has no
      # meaningful percentage, and 0/0 = 100% would be a lie in the flattering
      # direction.
      def utilization
        return nil if expected.zero?

        ((logged / expected) * 100).round
      end

      def empty?
        logged.zero?
      end
    end
  end
end
