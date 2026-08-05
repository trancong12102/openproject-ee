module Worklogs
  module Reports
    # The same report, one row per time entry instead of one row per group.
    #
    # A pivot answers "how much"; this answers "which entries", which is what
    # anybody billing, auditing or reconciling a month actually needs to hand
    # to somebody else. Same scope, same filters, same permission boundary.
    class DetailData
      include ActionView::Helpers::NumberHelper
      include Worklogs::ReportsHelper

      MAX_ROWS = 10_000
      BATCH = 500

      Row = Struct.new(:values, keyword_init: true)

      attr_reader :result

      def initialize(result:)
        @result = result
      end

      def query = result.query
      def scope = result.scope
      def costs_visible? = scope.costs_visible?

      def header
        columns = [
          I18n.t("worklogs.reports.detail.date"),
          I18n.t("worklogs.reports.dimensions.user"),
          I18n.t("worklogs.reports.dimensions.project"),
          I18n.t("worklogs.reports.detail.reference"),
          I18n.t("worklogs.reports.dimensions.entity"),
          I18n.t("worklogs.reports.dimensions.type"),
          I18n.t("worklogs.reports.dimensions.status"),
          I18n.t("worklogs.reports.dimensions.activity"),
          I18n.t("worklogs.reports.measures.hours")
        ]
        columns << I18n.t("worklogs.reports.measures.costs") if costs_visible?
        columns << I18n.t("worklogs.reports.detail.comment")
      end

      # Batched by hand rather than with `find_each`, which would force primary
      # key order and quietly shuffle the export out of date order.
      def each_row
        offset = 0

        while offset < MAX_ROWS
          batch = entries.offset(offset).limit([BATCH, MAX_ROWS - offset].min).to_a
          break if batch.empty?

          batch.each { |entry| yield row_for(entry) }
          offset += batch.size
        end
      end

      def count
        @count ||= entries.count
      end

      def truncated?
        count > MAX_ROWS
      end

      def notes
        return [] unless truncated?

        [I18n.t("worklogs.reports.detail.truncated", shown: MAX_ROWS, total: count)]
      end

      def total_hours
        @total_hours ||= entries.sum(:hours).to_f.round(2)
      end

      private

      def entries
        @entries ||= scope.relation
                          .except(:order)
                          .includes(:user, :activity, :project, entity: %i[type status])
                          .order(spent_on: :asc, id: :asc)
      end

      def row_for(entry)
        work_package = entry.entity if entry.entity.is_a?(WorkPackage)

        values = [
          entry.spent_on,
          entry.user&.name,
          entry.project&.name,
          reference(entry, work_package),
          subject(entry),
          work_package&.type&.name,
          work_package&.status&.name,
          entry.activity&.name,
          entry.hours.to_f.round(2)
        ]
        values << (entry.overridden_costs || entry.costs || 0).to_f.round(2) if costs_visible?
        values << entry.comments.to_s

        Row.new(values:)
      end

      # "#1234" is what people paste into a search box, so it gets its own
      # column rather than being buried in the subject.
      def reference(entry, work_package)
        return "##{work_package.id}" if work_package

        entry.entity_type
      end

      def subject(entry)
        entity = entry.entity
        return nil if entity.nil?

        entity.respond_to?(:subject) ? entity.subject : entity.to_s
      end
    end
  end
end
