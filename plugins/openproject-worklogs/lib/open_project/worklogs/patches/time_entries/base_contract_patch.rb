module OpenProject
  module Worklogs
    module Patches
      module TimeEntries
        # A locked week has to be locked everywhere, not just in this plugin's
        # own grid: the work package "log time" dialog, the my-time-tracking
        # page, the API and anything added later all end up here, at core's own
        # contract, and this is the only place that catches all of them.
        module BaseContractPatch
          extend ActiveSupport::Concern

          included do
            validate :validate_worklogs_period_open
          end

          private

          def validate_worklogs_period_open
            return if locked_dates.empty?

            errors.add(:base, I18n.t("worklogs.approval.error_period_locked",
                                     dates: locked_dates.map { |date| I18n.l(date, format: :long) }.uniq.join(", ")))
          end

          # Both the day it is going to and the day it came from: moving an
          # entry out of an approved week changes that week's total just as
          # surely as deleting it would.
          def locked_dates
            owner_id = model.user_id_was || model.user_id

            [[owner_id, model.spent_on_was], [model.user_id, model.spent_on]]
              .uniq
              .select { |user_id, date| date.present? && ::Worklogs::PeriodLock.locked?(user_id:, on: date) }
              .map(&:last)
          end
        end
      end
    end
  end
end
