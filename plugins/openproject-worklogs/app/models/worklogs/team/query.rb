module Worklogs
  module Team
    # Which people, over which span, sliced how.
    #
    # Like every other page in this plugin, the team sheet is its URL: the
    # expanded rows are in it too, so a manager can send somebody "look at this
    # week, at these two people, opened up" as a link and not as instructions.
    class Query
      # A team sheet is a table a person reads, not a dataset. Past a hundred
      # rows nobody is reading it, and it is the filters that are wrong.
      MAX_USERS = 100
      # Each expansion is a query and thirty-one more columns of markup.
      MAX_EXPANDED = 5

      SCOPES = %w[logged everyone].freeze
      SORTS = %w[name hours].freeze

      DEFAULTS = { scope: "logged", sort: "name" }.freeze

      attr_reader :span, :scope, :sort, :user_ids, :project_ids, :activity_ids, :expanded_ids

      delegate :dates, :range, :weeks, to: :span

      class << self
        def from_params(params)
          new(span: Span.from_params(params),
              scope: params[:scope], sort: params[:sort],
              user_ids: params[:user_ids], project_ids: params[:project_ids],
              activity_ids: params[:activity_ids], expand: params[:expand])
        end
      end

      def initialize(span:, scope: nil, sort: nil, user_ids: nil, project_ids: nil,
                     activity_ids: nil, expand: nil)
        @span = span
        @scope = SCOPES.include?(scope.to_s) ? scope.to_s : DEFAULTS[:scope]
        @sort = SORTS.include?(sort.to_s) ? sort.to_s : DEFAULTS[:sort]
        @user_ids = integer_list(user_ids)
        @project_ids = integer_list(project_ids)
        @activity_ids = integer_list(activity_ids)
        @expanded_ids = integer_list(expand).first(MAX_EXPANDED)
      end

      def everyone?
        scope == "everyone"
      end

      def by_hours?
        sort == "hours"
      end

      def expanded?(user)
        expanded_ids.include?(user.id)
      end

      def filters?
        [user_ids, project_ids, activity_ids].any?(&:any?) || everyone?
      end

      def filter_count
        [user_ids, project_ids, activity_ids].sum(&:size)
      end

      # Defaults are left out: a URL should say what is unusual about the page,
      # not restate everything that is ordinary about it.
      def to_params
        span.to_params
            .merge(user_ids:, project_ids:, activity_ids:, expand: expanded_ids)
            .merge(scope: (scope unless scope == DEFAULTS[:scope]),
                   sort: (sort unless sort == DEFAULTS[:sort]))
            .compact_blank
      end

      def merge(overrides)
        self.class.from_params(to_params.merge(overrides.symbolize_keys))
      end

      # A span replaces a span whole, dates included — merging one in would
      # leave last month's date under this week's name.
      def with_span(other)
        self.class.from_params(to_params.except(:span, :date).merge(other.to_params))
      end

      # Expanding is a link like everything else, so it survives the back
      # button and can be sent to somebody.
      def toggling(user)
        merge(expand: expanded?(user) ? expanded_ids - [user.id] : expanded_ids + [user.id])
      end

      def selected_ids(name)
        public_send(:"#{name}_ids")
      end

      private

      def integer_list(values)
        Array(values).flat_map { |value| value.to_s.split(",") }
                     .filter_map { |value| Integer(value, exception: false) }
                     .uniq
      end
    end
  end
end
