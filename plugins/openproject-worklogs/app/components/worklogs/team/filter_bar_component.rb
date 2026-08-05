module Worklogs
  module Team
    # The controls above the team sheet: which people, which of their work,
    # a week or a month, and whether the people with nothing are worth a line.
    #
    # Same `<details>`-wrapping-a-GET-form shape as the other three bars in this
    # plugin, so it works with no JavaScript and so learning one is learning all
    # of them.
    class FilterBarComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TeamHelper
      include OpPrimer::ComponentHelpers

      MAX_OPTIONS = 500

      options :query, :viewer

      delegate :span, to: :query

      Filter = Struct.new(:name, :label, :options, keyword_init: true)
      Option = Struct.new(:id, :label, keyword_init: true)

      def spans
        Span::KINDS
      end

      # A week carries no span in its URL, so switching back to one has to
      # clear the month explicitly.
      def span_href(kind)
        worklogs_team_href(query.with_span(Span.switch(span, kind)))
      end

      def span_selected?(kind)
        span.kind == kind
      end

      def scopes
        Query::SCOPES
      end

      def scope_href(scope)
        worklogs_team_href(query, scope:)
      end

      def scope_selected?(scope)
        query.scope == scope
      end

      def sorts
        Query::SORTS
      end

      def sort_href(sort)
        worklogs_team_href(query, sort:)
      end

      def sort_selected?(sort)
        query.sort == sort
      end

      def filters
        @filters ||= [
          Filter.new(name: :user, label: I18n.t("worklogs.reports.dimensions.user"),
                     options: user_options),
          Filter.new(name: :project, label: I18n.t("worklogs.reports.dimensions.project"),
                     options: project_options),
          Filter.new(name: :activity, label: I18n.t("worklogs.reports.dimensions.activity"),
                     options: activity_options)
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

      def clear_href(filter)
        worklogs_team_href(query, :"#{filter.name}_ids" => [])
      end

      def clear_all_href
        worklogs_team_href(query, user_ids: [], project_ids: [], activity_ids: [])
      end

      def filtered?
        query.filter_count.positive?
      end

      def filter_count
        query.filter_count
      end

      private

      # Everybody who could be asked to log time, not everybody who did: the
      # people worth picking on this page include the one with an empty week.
      def user_options
        User.active.not_builtin.order(:lastname, :firstname).limit(MAX_OPTIONS).map do |user|
          Option.new(id: user.id, label: user.name)
        end
      end

      def project_options
        Project.active.order(:name).limit(MAX_OPTIONS).map do |project|
          Option.new(id: project.id, label: project.name)
        end
      end

      # What the team actually booked time under in this span. An activity
      # nobody used is a line in the picker that can only ever empty the table.
      def activity_options
        TimeEntryActivity.where(id: activity_ids_in_span).order(:position, :name).map do |activity|
          Option.new(id: activity.id, label: activity.name)
        end
      end

      def activity_ids_in_span
        TimeEntry.visible(viewer).where(spent_on: span.range).distinct.pluck(:activity_id).compact
      end
    end
  end
end
