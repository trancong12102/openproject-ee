module Worklogs
  module Reports
    # The controls above a report: period, filters, how it is sliced, what is
    # counted.
    #
    # Every dropdown is a plain `<details>` wrapping a GET form, so the whole
    # bar works with no JavaScript at all — the bundled script only adds
    # type-to-search and close-on-outside-click. That matters here because the
    # slim runtime image has no Angular and no Stimulus to fall back on.
    class FilterBarComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::ReportsHelper
      include OpPrimer::ComponentHelpers

      options :query, :result, :viewer

      Filter = Struct.new(:name, :label, :options, keyword_init: true)
      Option = Struct.new(:id, :label, :caption, keyword_init: true)

      def periods
        Query::PERIODS
      end

      def measures
        Query::MEASURES.reject { |measure| measure == "costs" && !costs_visible? }
      end

      def costs_visible?
        result.scope.costs_visible?
      end

      def filters
        @filters ||= [
          Filter.new(name: :project, label: I18n.t("worklogs.reports.dimensions.project"), options: project_options),
          Filter.new(name: :user, label: I18n.t("worklogs.reports.dimensions.user"), options: user_options),
          Filter.new(name: :activity, label: I18n.t("worklogs.reports.dimensions.activity"), options: activity_options),
          Filter.new(name: :type, label: I18n.t("worklogs.reports.dimensions.type"), options: type_options),
          Filter.new(name: :status, label: I18n.t("worklogs.reports.dimensions.status"), options: status_options)
        ]
      end

      def selected_ids(filter)
        query.selected_ids(filter.name)
      end

      def chip_value(filter)
        selected = selected_ids(filter)
        return I18n.t("worklogs.reports.filter_all") if selected.empty?
        return filter.options.find { |option| option.id == selected.first }&.label.to_s if selected.one?

        I18n.t("worklogs.reports.filter_selected", count: selected.size)
      end

      def dimension_options
        Dimension.all
      end

      def column_options
        Dimension.all
      end

      def row_key(level)
        query.row_keys[level]
      end

      def clear_href(filter)
        worklogs_report_path(query, :"#{filter.name}_ids" => [])
      end

      def clear_all_href
        worklogs_report_path(query, project_ids: [], user_ids: [], activity_ids: [],
                                    type_ids: [], status_ids: [])
      end

      Export = Struct.new(:label, :caption, :href, keyword_init: true)

      # Two shapes, three formats. The pivot for reading and for filing; every
      # entry for the person who has to reconcile it against an invoice.
      def pivot_exports
        [
          export(:csv, "csv", false),
          export(:xls, "xls", false),
          export(:pdf, "pdf", false)
        ]
      end

      def detail_exports
        [
          export(:detail_csv, "csv", true),
          export(:detail_xls, "xls", true)
        ]
      end

      def timesheet_href
        worklogs_root_path
      end

      def grouping_summary
        parts = query.row_dimensions.map(&:label)
        parts << I18n.t("worklogs.reports.by_column", dimension: query.column_dimension.label) if query.column_dimension

        parts.join(" › ")
      end

      private

      def export(key, format, detail)
        Export.new(label: I18n.t("worklogs.reports.exports.#{key}"),
                   caption: I18n.t("worklogs.reports.exports.#{key}_caption"),
                   href: worklogs_report_export_path(query, format, detail))
      end

      # The lists people actually pick from: who and what has time in this
      # period, not every record in the instance. A picker full of names with
      # nothing behind them is a picker nobody reads to the end.
      def user_options
        ids = distinct_ids(:user_id)

        User.where(id: ids).order(:lastname, :firstname).map do |user|
          Option.new(id: user.id, label: user.name)
        end
      end

      def project_options
        ids = distinct_ids(:project_id)

        Project.where(id: ids).order(:name).map do |project|
          Option.new(id: project.id, label: project.name)
        end
      end

      def activity_options
        ids = distinct_ids(:activity_id)

        TimeEntryActivity.where(id: ids).order(:position, :name).map do |activity|
          Option.new(id: activity.id, label: activity.name)
        end
      end

      def type_options
        ::Type.order(:position).map { |type| Option.new(id: type.id, label: type.name) }
      end

      def status_options
        Status.order(:position).map { |status| Option.new(id: status.id, label: status.name) }
      end

      # Deliberately ignores the filters themselves: a picker that hid the
      # options you did not pick could never be widened again.
      def distinct_ids(column)
        @distinct_ids ||= {}
        @distinct_ids[column] ||=
          TimeEntry.visible(viewer).where(spent_on: query.range).distinct.pluck(column).compact
      end
    end
  end
end
