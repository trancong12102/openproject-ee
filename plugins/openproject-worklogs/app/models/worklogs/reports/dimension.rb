module Worklogs
  module Reports
    # One way of slicing time entries: the SQL expression to group on, and how
    # to turn the resulting keys back into something a person can read and click.
    #
    # Everything is expressed as a single SQL expression per dimension so a
    # report is always one grouped query, however many ways it is sliced.
    class Dimension
      Label = Struct.new(:text, :short, :href, :caption, :sort_key, keyword_init: true)

      KEYS = %w[user project entity type status activity assignee priority version
                day week month quarter year].freeze
      TIME_KEYS = %w[day week month quarter year].freeze
      WORK_PACKAGE_KEYS = %w[type status assignee priority version].freeze

      class << self
        def find(key)
          key = key.to_s
          new(key) if KEYS.include?(key)
        end

        def all
          KEYS.map { |key| new(key) }
        end

        def time
          TIME_KEYS.map { |key| new(key) }
        end
      end

      attr_reader :key

      def initialize(key)
        @key = key.to_s
      end

      def label
        I18n.t("worklogs.reports.dimensions.#{key}")
      end

      def time?
        TIME_KEYS.include?(key)
      end

      # Whether grouping on this needs the work package join; only asked for
      # when the dimension is actually used, so a report by user never pays for
      # a join it does not read.
      def requires_work_package_join?
        WORK_PACKAGE_KEYS.include?(key)
      end

      def expression
        case key
        when "user" then "time_entries.user_id"
        when "project" then "time_entries.project_id"
        # Time can be logged on meetings as well as work packages, so the key
        # has to carry the type — two records may share an id.
        when "entity" then "(time_entries.entity_type || '-' || time_entries.entity_id)"
        when "type" then "work_packages.type_id"
        when "status" then "work_packages.status_id"
        when "assignee" then "work_packages.assigned_to_id"
        when "priority" then "work_packages.priority_id"
        when "version" then "work_packages.version_id"
        when "activity" then "time_entries.activity_id"
        when "day" then "time_entries.spent_on"
        else "date_trunc('#{key}', time_entries.spent_on)::date"
        end
      end

      # Batch-resolves a whole column of group keys in one query per dimension,
      # rather than one per row.
      def resolve(keys)
        keys = keys.compact.uniq
        return {} if keys.empty?

        case key
        when "user" then resolve_records(User.where(id: keys)) { |u| Label.new(text: u.name, href: user_path(u)) }
        when "project" then resolve_records(Project.where(id: keys)) { |p| Label.new(text: p.name, href: project_path(p)) }
        when "entity" then resolve_entities(keys)
        when "type" then resolve_records(::Type.where(id: keys)) { |t| Label.new(text: t.name) }
        when "status" then resolve_records(Status.where(id: keys)) { |s| Label.new(text: s.name) }
        when "activity" then resolve_records(TimeEntryActivity.where(id: keys)) { |a| Label.new(text: a.name) }
        when "assignee" then resolve_records(User.where(id: keys)) { |u| Label.new(text: u.name, href: user_path(u)) }
        when "priority" then resolve_records(IssuePriority.where(id: keys)) { |p| Label.new(text: p.name) }
        when "version" then resolve_versions(keys)
        else resolve_dates(keys)
        end
      end

      def ==(other)
        other.is_a?(Dimension) && other.key == key
      end
      alias eql? ==

      def hash
        key.hash
      end

      private

      def resolve_records(scope)
        scope.each_with_object({}) do |record, result|
          result[record.id.to_s] = yield(record)
        end
      end

      # Two projects may each have a "1.0", so the version carries the project
      # it belongs to as its caption.
      def resolve_versions(keys)
        Version.where(id: keys).includes(:project).each_with_object({}) do |version, result|
          result[version.id.to_s] = Label.new(text: version.name, caption: version.project&.name)
        end
      end

      def resolve_entities(keys)
        by_type = keys.group_by { |composite| composite.to_s.split("-", 2).first }

        result = {}
        (by_type["WorkPackage"] || []).each_slice(500) do |slice|
          ids = slice.map { |composite| composite.split("-", 2).last }
          WorkPackage.where(id: ids).includes(:type).find_each do |work_package|
            result["WorkPackage-#{work_package.id}"] =
              Label.new(text: work_package.subject,
                        href: work_package_path(work_package),
                        caption: "#{work_package.type&.name} ##{work_package.id}")
          end
        end
        (by_type["Meeting"] || []).each_slice(500) do |slice|
          ids = slice.map { |composite| composite.split("-", 2).last }
          Meeting.where(id: ids).find_each do |meeting|
            result["Meeting-#{meeting.id}"] =
              Label.new(text: meeting.title,
                        href: meeting_path(meeting),
                        caption: Meeting.model_name.human)
          end
        end
        result
      end

      def resolve_dates(keys)
        keys.each_with_object({}) do |raw, result|
          date = raw.is_a?(Date) ? raw : Date.parse(raw.to_s)
          result[raw.to_s] = Label.new(text: date_label(date), short: short_date_label(date), sort_key: date)
        rescue Date::Error
          next
        end
      end

      # Along the top of a chart there is room for a few characters, not for
      # "Mon 3 August 2026" thirty-one times over.
      def short_date_label(date)
        case key
        when "day" then I18n.l(date, format: "%-d %b")
        when "week" then "W#{date.cweek}"
        when "month" then I18n.l(date, format: "%b %Y")
        else date_label(date)
        end
      end

      def date_label(date)
        case key
        when "day" then "#{I18n.t('date.abbr_day_names')[date.wday]} #{I18n.l(date, format: :long)}"
        when "week" then I18n.t("worklogs.timesheet.week_number", number: date.cweek)
        when "month" then I18n.l(date, format: "%B %Y")
        when "quarter" then "Q#{((date.month - 1) / 3) + 1} #{date.year}"
        else date.year.to_s
        end
      end

      def routes
        @routes ||= Rails.application.routes.url_helpers
      end

      %i[user_path project_path work_package_path meeting_path].each do |helper|
        define_method(helper) { |record| routes.public_send(helper, record) }
      end
    end
  end
end
