module Worklogs
  module Reports
    # Everything a report is: what to count, over which entries, sliced how.
    #
    # Deliberately not an ActiveRecord: a report is a URL. Every control on the
    # page is a link back to the same action with different parameters, so the
    # back button, bookmarks and "copy this to a colleague" all work without a
    # single line of state-keeping.
    class Query
      PERIODS = Worklogs::Period::NAMES
      MEASURES = %w[hours costs entries].freeze
      MAX_ROW_LEVELS = 2

      DEFAULTS = {
        period: "this_month",
        measure: "hours",
        rows: %w[user],
        columns: nil
      }.freeze

      attr_reader :measure, :row_keys, :column_key, :report_id,
                  :user_ids, :project_ids, :activity_ids, :type_ids, :status_ids

      delegate :from, :to, :range, to: :period_object
      delegate :label, to: :period_object, prefix: :period

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
            status_ids: params[:status_ids],
            report: params[:report]
          )
        end
      end

      def initialize(period: nil, from: nil, to: nil, measure: nil, rows: nil, columns: nil,
                     user_ids: nil, project_ids: nil, activity_ids: nil, type_ids: nil, status_ids: nil,
                     report: nil)
        @period_object = Worklogs::Period.new(period, from:, to:, default: DEFAULTS[:period])
        @measure = MEASURES.include?(measure.to_s) ? measure.to_s : DEFAULTS[:measure]

        @row_keys = sanitise_dimensions(rows).first(MAX_ROW_LEVELS)
        @row_keys = DEFAULTS[:rows] if @row_keys.empty?
        @column_key = sanitise_dimensions([columns]).first

        @user_ids = integer_list(user_ids)
        @project_ids = integer_list(project_ids)
        @activity_ids = integer_list(activity_ids)
        @type_ids = integer_list(type_ids)
        @status_ids = integer_list(status_ids)
        @report_id = Integer(report.to_s, exception: false)
      end

      def period
        period_object.name
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

      def filters?
        [user_ids, project_ids, activity_ids, type_ids, status_ids].any?(&:any?)
      end

      def filter_count
        [user_ids, project_ids, activity_ids, type_ids, status_ids].sum(&:size)
      end

      # What the report *is*: the part that gets saved, and the part two reports
      # are compared on to decide whether one has been edited away from the other.
      # Only a custom range carries its dates. A preset is a question about
      # *now* — a saved "this month" that came back next month still meaning
      # August would be a saved report that quietly went stale.
      def definition_params
        {
          period:, measure:, rows: row_keys, columns: column_key,
          user_ids:, project_ids:, activity_ids:, type_ids:, status_ids:
        }.merge(period_object.to_params.except(:period)).compact_blank
      end

      # `report` rides along in the URL without changing a single row of the
      # result: it only says which saved report this page started from, so the
      # page can offer to save changes back to it after a filter is nudged.
      def to_params
        definition_params.merge(report: report_id).compact_blank
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

      attr_reader :period_object

      def sanitise_dimensions(keys)
        Array(keys).filter_map { |key| Dimension.find(key)&.key }.uniq
      end

      def integer_list(values)
        Array(values).flat_map { |value| value.to_s.split(",") }
                     .filter_map { |value| Integer(value, exception: false) }
                     .uniq
      end
    end
  end
end
