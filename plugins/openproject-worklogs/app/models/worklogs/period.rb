module Worklogs
  # What "last month" means, in one place.
  #
  # Both the report builder and the coverage page ask the same question of the
  # same presets, and two answers to "when does this quarter start" is one
  # answer too many.
  #
  # Three kinds of period, which is one more than it looks:
  #
  # * a **preset** — "this month", "last week" — is a question about *now*, and
  #   carries no dates. Saved and reopened next month it means next month.
  # * an **anchored** period — a week, month, quarter or year — carries the one
  #   date it is anchored to and always means that same span. This is what the
  #   arrows either side of the period chip produce, and what a month picker
  #   sets: "August 2026" rather than "whichever month it is when you look".
  # * a **custom** range is any two dates.
  #
  # Anchored periods are the reason stepping works at all. Without them "last
  # month" could only ever go back one step, because there is no name for the
  # month before it.
  class Period
    PRESETS = %w[this_week last_week this_month last_month last_30_days
                 this_quarter this_year last_year].freeze
    # `from` is the anchor: any date inside the span identifies it.
    ANCHORED = %w[week month quarter year].freeze
    NAMES = (PRESETS + ANCHORED + %w[custom]).freeze
    DEFAULT = "this_month".freeze

    # Which anchored period a preset steps into. "Last month" stepped back is
    # not "the month before last" — there is no such preset — it is July.
    STEPS = {
      "this_week" => "week", "last_week" => "week",
      "this_month" => "month", "last_month" => "month",
      "this_quarter" => "quarter",
      "this_year" => "year", "last_year" => "year"
    }.freeze

    attr_reader :name, :from, :to

    class << self
      def from_params(params, default: DEFAULT)
        new(params[:period], from: params[:from], to: params[:to], default:)
      end

      def valid?(name)
        NAMES.include?(name.to_s)
      end

      # An anchored period over the span containing `date`.
      def anchored(unit, date)
        new(unit, from: date.to_date.iso8601)
      end
    end

    def initialize(name, from: nil, to: nil, default: DEFAULT)
      @name = self.class.valid?(name) ? name.to_s : default
      assign_range(from, to)
    end

    def custom?
      name == "custom"
    end

    def anchored?
      ANCHORED.include?(name)
    end

    def preset?
      PRESETS.include?(name)
    end

    def range
      from..to
    end

    def dates
      range.to_a
    end

    def length
      (to - from).to_i + 1
    end

    def include?(date)
      range.cover?(date)
    end

    def label
      return range_label if custom?
      return anchored_label if anchored?

      I18n.t("worklogs.reports.periods.#{name}")
    end

    # The dates, for a preset that does not show them in its own name. Nobody
    # reading "last 30 days" can say what it covers without being told.
    def caption
      return nil if custom? || name == "month" || name == "year"

      range_label
    end

    # Only a custom range carries both its dates, and only an anchored period
    # carries one. A preset is a question about *now* — a saved "this month"
    # that came back next month still meaning August would be a bookmark that
    # quietly went stale.
    def to_params
      return { period: name, from: from.iso8601, to: to.iso8601 } if custom?
      return { period: name, from: from.iso8601 } if anchored?

      { period: name }
    end

    # One step back, one step forward. A preset resolves to the anchored period
    # it names — "this month" back one is July, and July back one is June — so
    # the arrows keep working however far you walk.
    def previous
      shift(-1)
    end

    def next
      shift(1)
    end

    # There is no "next" past the span containing today for anything that has
    # not happened yet. Stepping into it is allowed — a week ahead is a
    # legitimate thing to look at — this only says whether it is empty.
    def future?
      from > Time.zone.today
    end

    def ==(other)
      other.is_a?(Period) && other.name == name && other.from == from && other.to == to
    end
    alias eql? ==

    def hash
      [name, from, to].hash
    end

    private

    def shift(direction)
      unit = STEPS[name]
      return self.class.anchored(unit, step_anchor(unit, direction)) if unit
      return self.class.anchored(name, step_anchor(name, direction)) if anchored?

      # A custom range and "last 30 days" have no unit but do have a length,
      # so they step by their own width: 30 days back, 30 days forward.
      shift_by_length(direction)
    end

    def step_anchor(unit, direction)
      case unit
      when "week" then from + (7 * direction)
      when "month" then from >> direction
      when "quarter" then from >> (3 * direction)
      else from >> (12 * direction)
      end
    end

    def shift_by_length(direction)
      offset = length * direction

      self.class.new("custom", from: (from + offset).iso8601, to: (to + offset).iso8601)
    end

    def assign_range(raw_from, raw_to)
      if custom?
        @from = parse_date(raw_from) || Time.zone.today.beginning_of_month
        @to = parse_date(raw_to) || Time.zone.today
        @from, @to = @to, @from if @from > @to
      elsif anchored?
        @from, @to = anchored_range(parse_date(raw_from) || Time.zone.today)
      else
        @from, @to = preset_range
      end
    end

    # Accepts a full date and also the "2026-08" a month input sends, which is
    # not an ISO-8601 date and which `Date.iso8601` refuses.
    def parse_date(value)
      text = value.to_s
      return Date.iso8601("#{text}-01") if text.match?(/\A\d{4}-\d{2}\z/)

      Date.iso8601(text)
    rescue Date::Error
      nil
    end

    def anchored_range(anchor)
      case name
      when "week" then [anchor.beginning_of_week(Week.start_day), anchor.end_of_week(Week.start_day)]
      when "month" then [anchor.beginning_of_month, anchor.end_of_month]
      when "quarter" then [anchor.beginning_of_quarter, anchor.end_of_quarter]
      else [anchor.beginning_of_year, anchor.end_of_year]
      end
    end

    def anchored_label
      case name
      when "week" then "#{I18n.t('worklogs.timesheet.week_number', number: from.cweek)} · #{range_label}"
      when "month" then I18n.l(from, format: "%B %Y")
      when "quarter" then "Q#{((from.month - 1) / 3) + 1} #{from.year}"
      else from.year.to_s
      end
    end

    # "3 – 9 August 2026", not "3 August 2026 – 9 August 2026": the month and
    # year are only worth saying once when both ends share them.
    def range_label
      return "#{I18n.l(from, format: :long)} – #{I18n.l(to, format: :long)}" unless from.year == to.year

      if from.month == to.month
        "#{from.day} – #{I18n.l(to, format: :long)}"
      else
        "#{I18n.l(from, format: '%-d %b')} – #{I18n.l(to, format: :long)}"
      end
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
