module Worklogs
  module Team
    # One person's line across the span: what they logged each day, against
    # what the calendar asked of them.
    #
    # Two figures rather than one, and deliberately so. `capacity` is the whole
    # span; `expected` is only the part of it that has already happened, and it
    # is what the balance is measured against — a table that calls everybody
    # 32 hours short every Monday is a table nobody opens twice.
    class Row
      attr_reader :user, :hours, :targets, :capacity, :expected, :details

      def initialize(user:, hours: {}, targets: {}, capacity: 0.0, expected: 0.0, details: [])
        @user = user
        @hours = hours
        @targets = targets
        @capacity = capacity.to_f
        @expected = expected.to_f
        @details = details
      end

      def on(date)
        hours[date].to_f
      end

      # What this person was asked for that day — their own working hours, their
      # own holidays and their own absences. A weekend is everybody's; a Tuesday
      # off is not, so it is read per row and not per column.
      def target_on(date)
        targets[date].to_f
      end

      def off?(date)
        target_on(date).zero?
      end

      # Logged nothing on a day they were expected to work, and that day has
      # already happened. The only cell on this page worth a colour.
      def gap?(date)
        on(date).zero? && !off?(date) && date <= Time.zone.today
      end

      def logged
        @logged ||= hours.values.sum(&:to_f).round(2)
      end

      def difference
        (logged - expected).round(2)
      end

      def utilization
        return nil if capacity.zero?

        ((logged / capacity) * 100).round
      end

      def expanded?
        details.any?
      end

      def logged?
        logged.positive?
      end

      # Sorted on the name the table shows, so two people called Nguyen sit
      # where the reader expects them to.
      def sort_key
        [user.lastname.to_s, user.firstname.to_s, user.id]
      end
    end
  end
end
