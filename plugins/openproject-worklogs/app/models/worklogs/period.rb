module Worklogs
  # What "last month" means, in one place.
  #
  # Both the report builder and the coverage page ask the same question of the
  # same nine presets, and two answers to "when does this quarter start" is one
  # answer too many.
  class Period
    PRESETS = %w[this_week last_week this_month last_month last_30_days
                 this_quarter this_year last_year].freeze
    NAMES = (PRESETS + %w[custom]).freeze
    DEFAULT = "this_month".freeze

    attr_reader :name, :from, :to

    class << self
      def from_params(params, default: DEFAULT)
        new(params[:period], from: params[:from], to: params[:to], default:)
      end

      def valid?(name)
        NAMES.include?(name.to_s)
      end
    end

    def initialize(name, from: nil, to: nil, default: DEFAULT)
      @name = self.class.valid?(name) ? name.to_s : default
      assign_range(from, to)
    end

    def custom?
      name == "custom"
    end

    def range
      from..to
    end

    def dates
      range.to_a
    end

    def label
      return "#{I18n.l(from, format: :long)} – #{I18n.l(to, format: :long)}" if custom?

      I18n.t("worklogs.reports.periods.#{name}")
    end

    # Only a custom range carries its dates. A preset is a question about *now*
    # — a saved "this month" that came back next month still meaning August
    # would be a bookmark that quietly went stale.
    def to_params
      return { period: name } unless custom?

      { period: name, from: from.iso8601, to: to.iso8601 }
    end

    def ==(other)
      other.is_a?(Period) && other.name == name && other.from == from && other.to == to
    end

    private

    def assign_range(raw_from, raw_to)
      if custom?
        @from = parse_date(raw_from) || Time.zone.today.beginning_of_month
        @to = parse_date(raw_to) || Time.zone.today
        @from, @to = @to, @from if @from > @to
      else
        @from, @to = preset_range
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end

    def preset_range # rubocop:disable Metrics/AbcSize
      today = Time.zone.today
      week_start = Week.start_day

      case name
      when "this_week" then [today.beginning_of_week(week_start), today.end_of_week(week_start)]
      when "last_week" then [(today - 7).beginning_of_week(week_start), (today - 7).end_of_week(week_start)]
      when "last_month" then [today.last_month.beginning_of_month, today.last_month.end_of_month]
      when "last_30_days" then [today - 29, today]
      when "this_quarter" then [today.beginning_of_quarter, today.end_of_quarter]
      when "this_year" then [today.beginning_of_year, today.end_of_year]
      when "last_year" then [today.last_year.beginning_of_year, today.last_year.end_of_year]
      else [today.beginning_of_month, today.end_of_month]
      end
    end
  end
end
