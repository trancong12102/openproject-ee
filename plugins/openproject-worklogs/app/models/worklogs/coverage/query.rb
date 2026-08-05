module Worklogs
  module Coverage
    # Who was supposed to log time, and did they.
    #
    # Like a report, this is a URL and nothing else: every control on the page
    # is a link back to the same action with one parameter changed.
    class Query
      GROUPINGS = %w[week day month].freeze
      SCOPES = %w[everyone missing complete].freeze

      DEFAULTS = { period: "this_month", group_by: "week", scope: "everyone" }.freeze

      attr_reader :group_by, :scope, :user_ids, :project_ids, :period_object

      delegate :from, :to, :range, :dates, to: :period_object
      delegate :label, to: :period_object, prefix: :period

      class << self
        def from_params(params)
          new(period: params[:period], from: params[:from], to: params[:to],
              group_by: params[:group_by], scope: params[:scope],
              user_ids: params[:user_ids], project_ids: params[:project_ids])
        end
      end

      def initialize(period: nil, from: nil, to: nil, group_by: nil, scope: nil,
                     user_ids: nil, project_ids: nil)
        @period_object = Worklogs::Period.new(period, from:, to:, default: DEFAULTS[:period])
        @group_by = GROUPINGS.include?(group_by.to_s) ? group_by.to_s : DEFAULTS[:group_by]
        @scope = SCOPES.include?(scope.to_s) ? scope.to_s : DEFAULTS[:scope]
        @user_ids = integer_list(user_ids)
        @project_ids = integer_list(project_ids)
      end

      def period
        period_object.name
      end

      def filters?
        [user_ids, project_ids].any?(&:any?)
      end

      def filter_count
        [user_ids, project_ids].sum(&:size)
      end

      def missing_only?
        scope == "missing"
      end

      def complete_only?
        scope == "complete"
      end

      def to_params
        { group_by:, scope:, user_ids:, project_ids: }
          .merge(period_object.to_params)
          .compact_blank
      end

      def merge(overrides)
        self.class.from_params(to_params.merge(overrides.symbolize_keys))
      end

      # A period replaces a period whole; merging one in would leave the old
      # dates behind, under the new period's name.
      def with_period(period)
        self.class.from_params(to_params.except(:period, :from, :to).merge(period.to_params))
      end

      def with_filter(name, values)
        merge(name => Array(values).reject(&:blank?))
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
