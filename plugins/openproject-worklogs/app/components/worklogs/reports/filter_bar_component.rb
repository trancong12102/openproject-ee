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

      # A picker nobody can read to the end is a picker nobody uses, and a
      # <select> with every work package in it is a page nobody can load. What
      # is left out is said out loud rather than quietly dropped.
      MAX_OPTIONS = 200

      options :query, :result, :viewer

      Filter = Struct.new(:name, :label, :options, :note, keyword_init: true)
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

      # One step back, one step forward, whatever the period is. A preset steps
      # into the anchored period it names, so "this month" back one is July and
      # July back one is June — see Worklogs::Period.
      def previous_period_href
        worklogs_reports_path(query.with_period(query.period_object.previous).to_params)
      end

      def next_period_href
        worklogs_reports_path(query.with_period(query.period_object.next).to_params)
      end

      def previous_period_label
        I18n.t("worklogs.reports.previous_period", period: query.period_object.previous.label)
      end

      def next_period_label
        I18n.t("worklogs.reports.next_period", period: query.period_object.next.label)
      end

      def period_caption
        query.period_object.caption
      end

      # What a month input needs: "2026-08". Anything that is not already a
      # month opens the picker on the month it starts in.
      def month_value
        query.from.strftime("%Y-%m")
      end

      def filters
        @filters ||= [
          Filter.new(name: :project, label: dimension_label(:project), options: project_options),
          Filter.new(name: :user, label: dimension_label(:user), options: user_options),
          Filter.new(name: :activity, label: dimension_label(:activity), options: activity_options),
          Filter.new(name: :work_package, label: dimension_label(:entity), **work_package_filter),
          Filter.new(name: :type, label: dimension_label(:type), options: type_options),
          Filter.new(name: :status, label: dimension_label(:status), options: status_options),
          Filter.new(name: :assignee, label: dimension_label(:assignee), options: assignee_options),
          Filter.new(name: :priority, label: dimension_label(:priority), options: priority_options),
          Filter.new(name: :version, label: dimension_label(:version), options: version_options)
        ]
      end

      def selected_ids(filter)
        query.selected_ids(filter.name)
      end

      def chip_value(filter)
        selected = selected_ids(filter)
        return I18n.t("worklogs.reports.filter_all") if selected.empty?

        if selected.one?
          label = filter.options.find { |option| option.id == selected.first }&.label
          return label if label.present?
        end

        I18n.t("worklogs.reports.filter_selected", count: selected.size)
      end

      # A selected option that has fallen outside the period — a work package
      # with no time logged this month — still has to be listed, or applying
      # any other filter would silently drop it from the URL.
      def options_for(filter)
        missing = selected_ids(filter) - filter.options.map(&:id)
        return filter.options if missing.empty?

        filter.options + missing.map { |id| Option.new(id:, label: "##{id}") }
      end

      def text_chip_value
        query.text.presence || I18n.t("worklogs.reports.filter_any")
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
        cleared = Query::FILTERS.to_h { |name| [:"#{name}_ids", []] }.merge(text: nil)

        worklogs_report_path(query, cleared)
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

      def dimension_label(key)
        I18n.t("worklogs.reports.dimensions.#{key}")
      end

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

      def priority_options
        IssuePriority.order(:position).map { |priority| Option.new(id: priority.id, label: priority.name) }
      end

      def assignee_options
        ids = work_package_column(:assigned_to_id)
        people = User.where(id: ids).order(:lastname, :firstname).map do |user|
          Option.new(id: user.id, label: user.name)
        end

        # Time logged on work packages nobody owns is exactly what a lead
        # looking for unowned effort is after, so it gets its own entry rather
        # than being unreachable.
        people.unshift(Option.new(id: Scope::UNASSIGNED, label: I18n.t("worklogs.reports.unassigned")))
      end

      def version_options
        ids = work_package_column(:version_id)

        Version.where(id: ids).includes(:project).sort_by { |version| version.name.to_s }.map do |version|
          Option.new(id: version.id, label: version.name, caption: version.project&.name)
        end
      end

      # The one list that can genuinely run to thousands, so it is capped and
      # says so. Newest first: the work package somebody is looking for is far
      # more often this week's than last year's.
      def work_package_filter
        ids = work_package_ids
        scope = WorkPackage.where(id: ids).includes(:type).order(id: :desc)

        options = scope.limit(MAX_OPTIONS).map do |work_package|
          Option.new(id: work_package.id, label: work_package.subject,
                     caption: "#{work_package.type&.name} ##{work_package.id}")
        end

        note = (I18n.t("worklogs.reports.options_capped", shown: MAX_OPTIONS, total: ids.size) if
          ids.size > MAX_OPTIONS)

        { options:, note: }
      end

      def work_package_ids
        @work_package_ids ||= TimeEntry.visible(viewer)
                                       .where(spent_on: query.range, entity_type: "WorkPackage")
                                       .distinct.pluck(:entity_id)
      end

      def work_package_column(column)
        return [] if work_package_ids.empty?

        WorkPackage.where(id: work_package_ids).distinct.pluck(column).compact
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
