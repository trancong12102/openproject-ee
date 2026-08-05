module Worklogs
  module Team
    # The team sheet as rows of values — the one shape both the CSV and the
    # workbook are written from.
    #
    # Two writers walking the sheet themselves would be two chances to disagree
    # with each other and with the screen, which is exactly the bug nobody
    # notices until a total is quoted in a meeting.
    class ExportTable
      # Where the figures start: person, work package, then a column per day.
      NUMERIC_FROM = 2

      Line = Struct.new(:values, :kind, keyword_init: true) do
        def total? = kind == :total
      end

      attr_reader :sheet

      def initialize(sheet:)
        @sheet = sheet
      end

      def header
        [I18n.t("worklogs.reports.dimensions.user"),
         I18n.t("worklogs.team.work_package_column")] +
          dates.map { |date| date.iso8601 } +
          [I18n.t("worklogs.team.total"),
           I18n.t("worklogs.coverage.total_expected"),
           I18n.t("worklogs.team.difference"),
           I18n.t("worklogs.coverage.utilization")]
      end

      def lines
        sheet.rows.flat_map do |row|
          [Line.new(values: person_values(row), kind: :person)] +
            row.details.map { |detail| Line.new(values: detail_values(detail), kind: :detail) }
        end
      end

      def total_line
        Line.new(values: total_values, kind: :total)
      end

      def notes
        notes = ["#{I18n.t('worklogs.timesheet.span')}: #{sheet.span.to_param}",
                 I18n.t("worklogs.team.export_note")]
        notes << I18n.t("worklogs.team.truncated_users", count: Query::MAX_USERS) if sheet.truncated_users?
        notes
      end

      def dates
        sheet.dates
      end

      private

      def person_values(row)
        [row.user.name, nil] +
          dates.map { |date| row.on(date) } +
          [row.logged, row.expected, row.difference, row.utilization]
      end

      # A detail line carries no capacity of its own: capacity belongs to the
      # person, and repeating it here would invite somebody to add it up.
      def detail_values(detail)
        [nil, detail_label(detail)] +
          dates.map { |date| detail.cell(date).hours } +
          [detail.total, nil, nil, nil]
      end

      def detail_label(detail)
        [detail.reference, detail.subject, detail.activity&.name].compact.join(" ")
      end

      def total_values
        [I18n.t("worklogs.coverage.everyone"), nil] +
          dates.map { |date| sheet.daily_total(date) } +
          [sheet.total, sheet.expected, sheet.difference, sheet.utilization]
      end
    end
  end
end
