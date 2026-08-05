module Worklogs
  module Reports
    # Runs a report and shapes it into a pivot: a row tree, a column axis, and
    # a value at every crossing.
    #
    # One grouped query does all the arithmetic in the database, whatever the
    # slice; the only thing Ruby does afterwards is nest the rows and look up
    # names for the group keys, batched one query per dimension.
    class Result
      MAX_COLUMNS = 60
      MAX_ROWS = 250

      Column = Struct.new(:key, :label, keyword_init: true)

      Node = Struct.new(:key, :dimension, :label, :children, :values, :measures, :path, keyword_init: true) do
        def total
          measures[:value]
        end

        def leaf?
          children.empty?
        end

        def measure(key, column_key = nil)
          source = column_key ? values[column_key] : measures
          source&.dig(key) || 0
        end
      end

      attr_reader :query, :viewer

      def initialize(query:, viewer: User.current)
        @query = query
        @viewer = viewer
      end

      def scope
        @scope ||= Scope.new(query:, viewer:)
      end

      def nodes = load[:nodes]
      def columns = load[:columns]
      def column_totals = load[:column_totals]
      def totals = load[:totals]

      def grand_total
        totals[:value]
      end

      def empty?
        nodes.empty?
      end

      def columns?
        query.column_dimension.present?
      end

      # A year sliced by day is 365 columns nobody can read. Report the cut
      # rather than silently showing the first sixty.
      def truncated_columns = load[:truncated_columns]
      def truncated_rows = load[:truncated_rows]

      def measure_key
        query.measure.to_sym
      end

      private

      def load
        @load ||= begin
          rows = fetch
          columns, truncated_columns = build_columns(rows)
          nodes, truncated_rows = build_nodes(rows)

          { rows:, columns:, truncated_columns:, nodes:, truncated_rows:,
            column_totals: build_column_totals(rows), totals: build_totals(rows) }
        end
      end

      def fetch
        ActiveRecord::Base.connection.select_all(aggregate_relation.to_sql).to_a
      end

      def aggregate_relation
        selects = query.row_dimensions.each_with_index.map { |dimension, index| "#{dimension.expression} AS r#{index}" }
        selects << "#{query.column_dimension.expression} AS c" if columns?
        selects.concat(measure_selects)

        groups = query.row_dimensions.map(&:expression)
        groups << query.column_dimension.expression if columns?

        scope.relation
             .except(:order)
             .select(Arel.sql(selects.join(", ")))
             .group(Arel.sql(groups.join(", ")))
      end

      # All three measures come back every time. They cost one scan either way,
      # and having them lets the summary read "1,204 entries · 312h · €18,720"
      # without running the report three times.
      def measure_selects
        [
          "SUM(COALESCE(time_entries.hours, 0)) AS hours",
          "COUNT(time_entries.id) AS entries",
          "SUM(COALESCE(time_entries.overridden_costs, time_entries.costs, 0)) AS costs"
        ]
      end

      def measures_for(row)
        values = { hours: row["hours"].to_f.round(2),
                   entries: row["entries"].to_i,
                   costs: row["costs"].to_f.round(2) }
        values[:value] = values[measure_key]
        values
      end

      def merge_measures(into, from)
        into[:hours] = (into[:hours] + from[:hours]).round(2)
        into[:entries] += from[:entries]
        into[:costs] = (into[:costs] + from[:costs]).round(2)
        into[:value] = into[measure_key]
        into
      end

      def blank_measures
        { hours: 0.0, entries: 0, costs: 0.0, value: 0 }
      end

      def build_columns(rows)
        return [[], 0] unless columns?

        dimension = query.column_dimension
        keys = rows.map { |row| normalise(row["c"]) }.uniq
        labels = dimension.resolve(keys)
        ordered = order_keys(keys, dimension, labels)

        [ordered.first(MAX_COLUMNS).map { |key| Column.new(key:, label: label_for(labels, key)) },
         [ordered.size - MAX_COLUMNS, 0].max]
      end

      # Walks each result row down the level tree, adding its figures to every
      # node on the way. A collapsed level therefore always equals the sum of
      # what it hides, without a second pass to roll anything up.
      def build_nodes(rows)
        levels = query.row_dimensions
        labels = levels.each_with_index.map do |dimension, index|
          dimension.resolve(rows.map { |row| normalise(row["r#{index}"]) })
        end

        root = {}
        rows.each { |row| insert_row(root, row, levels, labels) }

        ordered = sort_level(root.values)
        [ordered.first(MAX_ROWS), [ordered.size - MAX_ROWS, 0].max]
      end

      def insert_row(root, row, levels, labels)
        measures = measures_for(row)
        column_key = columns? ? normalise(row["c"]) : nil

        bucket = root
        path = []

        levels.each_with_index do |dimension, index|
          key = normalise(row["r#{index}"])
          path += [[dimension, key]]

          node = bucket[key] ||= Node.new(key:, dimension:, label: label_for(labels[index], key),
                                          children: {}, values: {}, measures: blank_measures, path:)

          merge_measures(node.measures, measures)
          node.values[column_key] = merge_measures(node.values[column_key] || blank_measures, measures) if column_key

          bucket = node.children
        end
      end

      # Time reads chronologically; everything else reads biggest-first, because
      # the point of a report is the top of the list.
      def sort_level(nodes)
        sorted =
          if nodes.first&.dimension&.time?
            nodes.sort_by { |node| [node.label.sort_key || node.key.to_s, node.key.to_s] }
          else
            nodes.sort_by { |node| [-node.total.to_f, node.label.text.to_s] }
          end

        sorted.each { |node| node.children = sort_level(node.children.values) }
        sorted
      end

      def build_column_totals(rows)
        return {} unless columns?

        rows.each_with_object({}) do |row, totals|
          key = normalise(row["c"])
          totals[key] = merge_measures(totals[key] || blank_measures, measures_for(row))
        end
      end

      def build_totals(rows)
        rows.reduce(blank_measures) { |totals, row| merge_measures(totals, measures_for(row)) }
      end

      def order_keys(keys, dimension, labels)
        if dimension.time?
          keys.sort_by { |key| [label_for(labels, key).sort_key || key.to_s, key.to_s] }
        else
          keys.sort_by { |key| label_for(labels, key).text.to_s }
        end
      end

      def label_for(labels, key)
        labels[key] || Dimension::Label.new(text: key.presence || I18n.t("worklogs.reports.none"))
      end

      def normalise(value)
        value.nil? ? "" : value.to_s
      end
    end
  end
end
