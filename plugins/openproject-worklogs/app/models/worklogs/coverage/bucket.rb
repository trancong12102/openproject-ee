module Worklogs
  module Coverage
    # One column of the coverage table: a week, a day or a month, clipped to the
    # period being asked about.
    #
    # A week that only half overlaps the period is shown at its real length and
    # its real capacity — pretending a part-week is a whole one is how a
    # "missing time" page ends up accusing people of hours they were never
    # expected to log.
    class Bucket
      attr_reader :key, :dates

      def initialize(key:, dates:)
        @key = key
        @dates = dates
      end

      class << self
        def build(query)
          case query.group_by
          when "day" then days(query)
          when "month" then months(query)
          else weeks(query)
          end
        end

        private

        def days(query)
          query.dates.map { |date| new(key: date.iso8601, dates: [date]) }
        end

        def weeks(query)
          query.dates.group_by { |date| date.beginning_of_week(Week.start_day) }
               .map { |start_date, dates| new(key: start_date.iso8601, dates:) }
        end

        def months(query)
          query.dates.group_by(&:beginning_of_month)
               .map { |start_date, dates| new(key: start_date.iso8601, dates:) }
        end
      end

      def start_date
        dates.first
      end

      def end_date
        dates.last
      end

      def range
        start_date..end_date
      end

      def include?(date)
        range.cover?(date)
      end

      def past?(today = Time.zone.today)
        end_date < today
      end

      def future?(today = Time.zone.today)
        start_date > today
      end

      def current?(today = Time.zone.today)
        include?(today)
      end

      # Days that have already happened. What somebody is behind on is measured
      # against these, never against a Friday that has not arrived yet.
      def elapsed_dates(today = Time.zone.today)
        dates.take_while { |date| date <= today }
      end

      def label(group_by)
        case group_by
        when "day" then I18n.l(start_date, format: :long)
        when "month" then I18n.l(start_date, format: "%B %Y")
        else "#{I18n.t('worklogs.timesheet.week_number', number: start_date.cweek)} · " \
             "#{I18n.l(start_date, format: :short)} – #{I18n.l(end_date, format: :short)}"
        end
      end

      def short_label(group_by)
        case group_by
        when "day" then I18n.l(start_date, format: "%a %-d")
        when "month" then I18n.l(start_date, format: "%b %Y")
        else "W#{start_date.cweek}"
        end
      end
    end
  end
end
