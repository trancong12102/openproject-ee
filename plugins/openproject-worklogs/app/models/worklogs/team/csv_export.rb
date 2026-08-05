require "csv"

module Worklogs
  module Team
    # The team sheet as a spreadsheet: same people, same order, same figures,
    # one column per day.
    #
    # Numbers are written as numbers — a spreadsheet is opened to be re-summed,
    # and "7h 30m" cannot be. Expanded rows come along under their person, so
    # the file says as much as the screen it was taken from.
    class CsvExport
      attr_reader :sheet

      def initialize(sheet:)
        @sheet = sheet
      end

      def to_csv
        CSV.generate do |csv|
          csv << header
          sheet.rows.each do |row|
            csv << values_for(row.user.name, row)
            row.details.each { |detail| csv << detail_values(detail) }
          end
          csv << totals_row
          notes.each { |note| csv << [note] }
        end
      end

      private

      def dates
        sheet.dates
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

      def values_for(name, row)
        [name, nil] +
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

      def totals_row
        [I18n.t("worklogs.coverage.everyone"), nil] +
          dates.map { |date| sheet.daily_total(date) } +
          [sheet.total, sheet.expected, sheet.difference, sheet.utilization]
      end

      def notes
        notes = ["#{I18n.t('worklogs.timesheet.span')}: #{sheet.span.to_param}"]
        notes << I18n.t("worklogs.team.export_note")
        notes << I18n.t("worklogs.team.truncated_users", count: Query::MAX_USERS) if sheet.truncated_users?
        notes
      end
    end
  end
end
