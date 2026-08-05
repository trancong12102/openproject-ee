module Worklogs
  module Coverage
    # The controls above the coverage table. Same `<details>`-wrapping-a-GET-form
    # shape as the report bar, so the page works with no JavaScript at all.
    class FilterBarComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::CoverageHelper
      include OpPrimer::ComponentHelpers

      options :query, :result, :viewer

      Filter = Struct.new(:name, :label, :options, keyword_init: true)
      Option = Struct.new(:id, :label, keyword_init: true)

      def periods
        Worklogs::Period::NAMES
      end

      def groupings
        Query::GROUPINGS
      end

      def scopes
        Query::SCOPES
      end

      def filters
        @filters ||= [
          Filter.new(name: :project, label: I18n.t("worklogs.reports.dimensions.project"), options: project_options),
          Filter.new(name: :user, label: I18n.t("worklogs.reports.dimensions.user"), options: user_options)
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

      def clear_href(filter)
        worklogs_coverage_href(query, :"#{filter.name}_ids" => [])
      end

      def clear_all_href
        worklogs_coverage_href(query, project_ids: [], user_ids: [])
      end

      def export_href
        worklogs_coverage_export_href(query)
      end

      private

      # Everyone who could be asked to log time, not everyone who did. The
      # picker on a page about missing time has to be able to offer the person
      # with nothing behind their name.
      def user_options
        User.active.not_builtin.order(:lastname, :firstname).limit(500).map do |user|
          Option.new(id: user.id, label: user.name)
        end
      end

      def project_options
        Project.active.order(:name).limit(500).map do |project|
          Option.new(id: project.id, label: project.name)
        end
      end
    end
  end
end
