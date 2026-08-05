module Worklogs
  module Reports
    # Everything a report is: what to count, over which entries, sliced how.
    #
    # Deliberately not an ActiveRecord: a report is a URL. Every control on the
    # page is a link back to the same action with different parameters, so the
    # back button, bookmarks and "copy this to a colleague" all work without a
    # single line of state-keeping.
    class Query
      PERIODS = Worklogs::Period::PRESETS
      MEASURES = %w[hours costs entries].freeze
      MAX_ROW_LEVELS = 2

      # Every list filter, in the order they appear above the report. Adding one
      # here gives it a reader, a place in the URL, a chip in the bar and a line
      # in what gets saved; the only thing left is how it reaches SQL, which is
      # `Scope`'s business.
      FILTERS = %i[user project activity type status work_package assignee priority version].freeze

      DEFAULTS = {
        period: "this_month",
        measure: "hours",
        rows: %w[user],
        columns: nil
      }.freeze

      attr_reader :measure, :row_keys, :column_key, :report_id, :text, :period_object

      delegate :from, :to, :range, to: :period_object
      delegate :label, to: :period_object, prefix: :period

      FILTERS.each { |name| attr_reader :"#{name}_ids" }

      class << self
        def from_params(params)
          new(
            period: params[:period],
            from: params[:from],
            to: params[:to],
            measure: params[:measure],
            rows: Array(params[:rows]),
            columns: params[:columns],
            text: params[:text],
            report: params[:report],
            **FILTERS.index_with { |name| params[:"#{name}_ids"] }
          )
        end
      end

      def initialize(period: nil, from: nil, to: nil, measure: nil, rows: nil, columns: nil,
                     text: nil, report: nil, **filters)
        @period_object = Worklogs::Period.new(period, from:, to:, default: DEFAULTS[:period])
        @measure = MEASURES.include?(measure.to_s) ? measure.to_s : DEFAULTS[:measure]

        @row_keys = sanitise_dimensions(rows).first(MAX_ROW_LEVELS)
        @row_keys = DEFAULTS[:rows] if @row_keys.empty?
        @column_key = sanitise_dimensions([columns]).first

        FILTERS.each { |name| instance_variable_set(:"@#{name}_ids", integer_list(filters[name])) }

        # A search box that matched on one character would run the whole table
        # through a LIKE for nothing.
        @text = text.to_s.strip.presence
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

      def filter_ids
        FILTERS.map { |name| selected_ids(name) }
      end

      def filters?
        filter_ids.any?(&:any?) || text.present?
      end

      def filter_count
        filter_ids.sum(&:size) + (text.present? ? 1 : 0)
      end

      # Which filters need the work package table. Asked before the join is
      # added, so a report by user never pays for a join it does not read.
      def work_package_filters?
        [type_ids, status_ids, assignee_ids, priority_ids, version_ids].any?(&:any?)
      end

      # What the report *is*: the part that gets saved, and the part two reports
      # are compared on to decide whether one has been edited away from the other.
      def definition_params
        FILTERS.to_h { |name| [:"#{name}_ids", selected_ids(name)] }
               .merge(measure:, rows: row_keys, columns: column_key, text:)
               .merge(period_object.to_params)
               .compact_blank
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

      # A period replaces a period whole. Merging one in would leave the old
      # `from`/`to` behind, and a preset carrying somebody else's dates is a
      # report that shows one span under another span's name.
      def with_period(period)
        self.class.from_params(to_params.except(:period, :from, :to).merge(period.to_params))
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
    end
  end
end
