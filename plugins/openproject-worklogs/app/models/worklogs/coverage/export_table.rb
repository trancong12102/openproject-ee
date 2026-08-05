module Worklogs
  module Coverage
    # The coverage table as rows of values — the one shape both the CSV and the
    # workbook are written from.
    #
    # Three figures per bucket rather than the screen's one, because a colour is
    # not something you can sort a column by.
    class ExportTable
      # Everything after the person's name is a number.
      NUMERIC_FROM = 1

      Line = Struct.new(:values, :kind, keyword_init: true) do
        def total? = kind == :total
      end

      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def header
        [I18n.t("worklogs.reports.dimensions.user")] +
          result.buckets.flat_map do |bucket|
            label = bucket.label(query.group_by)
            [I18n.t("worklogs.coverage.logged_column", bucket: label),
             I18n.t("worklogs.coverage.expected_column", bucket: label),
             I18n.t("worklogs.coverage.missing_column", bucket: label)]
          end +
          [I18n.t("worklogs.coverage.total_logged"),
           I18n.t("worklogs.coverage.total_expected"),
           I18n.t("worklogs.coverage.total_missing"),
           I18n.t("worklogs.coverage.utilization")]
      end

      def lines
        result.rows.map { |row| Line.new(values: values_for(row, row.user.name), kind: :person) }
      end

      # The Missing column adds up to the sum of what individuals are short, not
      # to the team's net position: one person's overtime does not fill in
      # somebody else's empty Thursday.
      def total_line
        values = [I18n.t("worklogs.coverage.everyone")] +
                 result.totals.cells.each_with_index.flat_map do |cell, index|
                   [cell.logged, cell.expected, result.missing_by_bucket[index]]
                 end +
                 [result.totals.logged, result.totals.expected,
                  result.missing_hours, result.totals.utilization]

        Line.new(values:, kind: :total)
      end

      def notes
        notes = ["#{I18n.t('worklogs.reports.period')}: #{query.period_label}",
                 I18n.t("worklogs.coverage.export_note")]
        notes << I18n.t("worklogs.coverage.truncated_users", count: Result::MAX_USERS) if result.truncated_users?
        notes << I18n.t("worklogs.coverage.truncated_buckets", count: Result::MAX_BUCKETS) if result.truncated_buckets?
        notes
      end

      def query
        result.query
      end

      private

      def values_for(row, label)
        [label] +
          row.cells.flat_map { |cell| [cell.logged, cell.expected, cell.missing] } +
          [row.logged, row.expected, row.missing, row.utilization]
      end
    end
  end
end
