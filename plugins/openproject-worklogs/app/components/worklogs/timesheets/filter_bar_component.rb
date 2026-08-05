module Worklogs
  module Timesheets
    # The controls above the grid: whose sheet, week or month, and which slice
    # of it.
    #
    # Same `<details>`-wrapping-a-GET-form shape as the report and coverage
    # bars, so it works with no JavaScript at all — and so a person who has
    # learned one filter bar in this plugin has learned all three.
    class FilterBarComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper
      include OpPrimer::ComponentHelpers

      MAX_PEOPLE = 200

      options :timesheet

      delegate :span, :user, :viewer, to: :timesheet

      Filter = Struct.new(:name, :label, :options, keyword_init: true)
      Option = Struct.new(:id, :label, keyword_init: true)

      def spans
        Span::KINDS
      end

      # A week does not carry a span in its URL, so switching back to one has to
      # clear the month explicitly. `worklogs_timesheet_params` drops the nil.
      def span_href(kind)
        worklogs_timesheet_href(timesheet, { span: nil }.merge(Span.switch(span, kind).to_params))
      end

      def span_selected?(kind)
        span.kind == kind
      end

      # Only somebody who may look at another person's time is offered the
      # list; for everybody else the sheet is their own and the picker would be
      # a control with one entry.
      def people?
        viewer.allowed_in_any_project?(:view_time_entries)
      end

      def people
        @people ||= User.active.not_builtin.order(:lastname, :firstname).limit(MAX_PEOPLE).to_a
      end

      def person_href(person)
        worklogs_timesheet_href(timesheet, user_id: person.id)
      end

      def filters
        @filters ||= [
          Filter.new(name: :project, label: I18n.t("worklogs.reports.dimensions.project"),
                     options: project_options),
          Filter.new(name: :activity, label: I18n.t("worklogs.reports.dimensions.activity"),
                     options: activity_options)
        ]
      end

      def selected_ids(filter)
        filter.name == :project ? timesheet.project_ids : timesheet.activity_ids
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
        worklogs_timesheet_href(timesheet, :"#{filter.name}_ids" => [])
      end

      def clear_all_href
        worklogs_timesheet_href(timesheet, project_ids: [], activity_ids: [])
      end

      def filtered?
        timesheet.filtered?
      end

      def filter_count
        timesheet.filter_count
      end

      private

      # What this person has actually logged in this span, unfiltered — a
      # picker built from the filtered set could never be widened again.
      def project_options
        Project.where(id: entry_ids(:project_id)).order(:name).map do |project|
          Option.new(id: project.id, label: project.name)
        end
      end

      def activity_options
        TimeEntryActivity.where(id: entry_ids(:activity_id)).order(:position, :name).map do |activity|
          Option.new(id: activity.id, label: activity.name)
        end
      end

      def entry_ids(column)
        @entry_ids ||= {}
        @entry_ids[column] ||= TimeEntry.where(user_id: user.id, spent_on: span.range)
                                        .distinct.pluck(column).compact
      end
    end
  end
end
