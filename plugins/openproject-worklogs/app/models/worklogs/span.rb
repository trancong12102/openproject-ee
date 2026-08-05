module Worklogs
  # Which stretch of days a timesheet is showing: a week or a month.
  #
  # One place decides, because four controllers and a dozen links all have to
  # agree on what `?span=month&date=2026-08-01` means. Anything unrecognised is
  # a week — the URL is user-editable, and the wrong answer to a typo should be
  # the ordinary view rather than an error page.
  module Span
    KINDS = %w[week month].freeze
    DEFAULT = "week".freeze

    class << self
      def from_params(params)
        for_kind(params[:span], params[:date])
      end

      def for_kind(kind, date = nil)
        kind(kind) == "month" ? Month.from_param(date) : Week.from_param(date)
      end

      def kind(value)
        KINDS.include?(value.to_s) ? value.to_s : DEFAULT
      end

      # Switching week ↔ month keeps you where you were standing: the month
      # containing the week you were looking at, and the week containing the
      # first of the month — or today's week, when the month is this one.
      def switch(span, kind)
        return span if span.kind == kind(kind)
        return Month.containing(span.start_date) if kind(kind) == "month"

        Week.containing(span.include?(Time.zone.today) ? Time.zone.today : span.start_date)
      end
    end
  end
end
