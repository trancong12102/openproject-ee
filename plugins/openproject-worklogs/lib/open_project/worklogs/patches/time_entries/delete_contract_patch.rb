module OpenProject
  module Worklogs
    module Patches
      module TimeEntries
        # Deleting an entry out of an approved week is the same act as editing
        # one, from the week total's point of view. The delete contract does not
        # inherit from the base contract, so it has to be told separately.
        module DeleteContractPatch
          extend ActiveSupport::Concern

          included do
            validate :validate_worklogs_period_open
          end

          private

          def validate_worklogs_period_open
            return unless ::Worklogs::PeriodLock.locked?(user_id: model.user_id, on: model.spent_on)

            errors.add(:base, I18n.t("worklogs.approval.error_period_locked",
                                     dates: I18n.l(model.spent_on, format: :long)))
          end
        end
      end
    end
  end
end
