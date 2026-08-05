module Worklogs
  module Team
    # Four figures about the team, on the same rule as the personal sheet: the
    # balance is measured against what was owed *by today*, not against the
    # whole span, or every Monday would read as a crisis.
    class SummaryComponent < ApplicationComponent
      include OpTurbo::Streamable
      include Worklogs::TimesheetHelper

      options :sheet

      delegate :span, :total, :capacity, :expected, :difference, :utilization,
               :people_count, :logged_count, to: :sheet

      def logged_label
        I18n.t("worklogs.stats.logged.#{span.kind}")
      end

      def progress
        return 0 if capacity.zero?

        [(total / capacity * 100).round, 100].min
      end

      def difference_label
        return "±0h" if difference.zero?

        "#{difference.positive? ? '+' : '−'}#{worklogs_duration(difference.abs)}"
      end

      def difference_scheme
        return "success" if difference >= 0
        return "attention" if difference > -8

        "danger"
      end

      def utilization_label
        return "–" if utilization.nil?

        "#{utilization}%"
      end

      # People, not rows: with the scope on "everybody" the difference between
      # the two is the whole point of the page.
      def people_caption
        I18n.t("worklogs.team.people_caption", logged: logged_count, total: people_count)
      end
    end
  end
end
