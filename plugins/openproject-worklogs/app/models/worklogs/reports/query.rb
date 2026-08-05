module Worklogs
  module Reports
    # Everything a report is: what to count, over which entries, sliced how.
    #
    # Deliberately not an ActiveRecord: a report is a URL. Every control on the
    # page is a link back to the same action with different parameters, so the
    # back button, bookmarks and "copy this to a colleague" all work without a
    # single line of state-keeping.
    class Query
      PERIODS = %w[this_week last_week this_month last_month last_30_days
                   this_quarter this_year last_year custom].freeze
      MEASURES = %w[hours costs entries].freeze
      MAX_ROW_LEVELS = 2

      DEFAULTS = {
        period: "this_month",
        measure: "hours",
        rows: %w[user],
        columns: nil
      }.freeze

      attr_reader :period, :measure, :row_keys, :column_key,
                  :user_ids, :project_ids, :activity_ids, :type_ids, :status_ids
      attr_accessor :from, :to

      class << self
        def from_params(params)
          new(
            period: params[:period],
            from: params[:from],
            to: params[:to],
            measure: params[:measure],
            rows: Array(params[:rows]),
            columns: params[:columns],
            user_ids: params[:user_ids],
            project_ids: params[:project_ids],
            activity_ids: params[:activity_ids],
            type_ids: params[:type_ids],
            status_ids: params[:status_ids]
          )
        end
      end

      def initialize(period: nil, from: nil, to: nil, measure: nil, rows: nil, columns: nil,
                     user_ids: nil, project_ids: nil, activity_ids: nil, type_ids: nil, status_ids: nil)
        @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULTS[:period]
        @measure = MEASURES.include?(measure.to_s) ? measure.to_s : DEFAULTS[:measure]

        @row_keys = sanitise_dimensions(rows).first(MAX_ROW_LEVELS)
        @row_keys = DEFAULTS[:rows] if @row_keys.empty?
        @column_key = sanitise_dimensions([columns]).first

        @user_ids = integer_list(user_ids)
        @project_ids = integer_list(project_ids)
        @activity_ids = integer_list(activity_ids)
        @type_ids = integer_list(type_ids)
        @status_ids = integer_list(status_ids)

        assign_range(from, to)
      end

      def row_dimensions
        @row_dimensions ||= row_keys.filter_map { |key| Dimension.find(key) }
      end

      def column_dimension
        @column_dimension ||= column_key && Dimension.find(column_key)
      end

      def dimensions
        (row_dimensions + [column_dimension]).compact
      end

      def range
        from..to
      end

      def filters?
        [user_ids, project_ids, activity_ids, type_ids, status_ids].any?(&:any?)
      end

      def filter_count
        [user_ids, project_ids, activity_ids, type_ids, status_ids].sum(&:size)
      end

      def period_label
        return "#{I18n.l(from, format: :long)} – #{I18n.l(to, format: :long)}" if period == "custom"

        I18n.t("worklogs.reports.periods.#{period}")
      end

      def to_params
        {
          period:, from: from.iso8601, to: to.iso8601, measure:,
          rows: row_keys, columns: column_key,
          user_ids:, project_ids:, activity_ids:, type_ids:, status_ids:
        }.compact_blank
      end

      # Every control on the page is "this report, with one thing changed".
      def merge(overrides)
        self.class.from_params(to_params.merge(overrides.symbolize_keys))
      end

      def with_filter(name, values)
        merge(name => Array(values).reject(&:blank?))
      end

      def selected_ids(name)
        public_send(:"#{name}_ids")
      end

      private

      def sanitise_dimensions(keys)
        Array(keys).filter_map { |key| Dimension.find(key)&.key }.uniq
      end

      def integer_list(values)
        Array(values).flat_map { |value| value.to_s.split(",") }
                     .filter_map { |value| Integer(value, exception: false) }
                     .uniq
      end

      def assign_range(raw_from, raw_to)
        if period == "custom"
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

        case period
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
end
