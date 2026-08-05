module Worklogs
  # Whether a given day of a given person's time is closed to changes.
  #
  # Asked from three places that must never disagree: the grid (to render
  # read-only), the plugin's own endpoints (to refuse), and core's time entry
  # contracts (to refuse everything else — the API, the work package dialog,
  # the "log time" button, and anything added later).
  class PeriodLock
    class << self
      def locked?(user_id:, on:)
        return false if user_id.blank? || on.blank?

        cache.fetch([user_id, on]) do
          Submission.locked.where(user_id:).covering(on).exists?
        end
      end

      def submission_for(user_id:, on:)
        Submission.covering(on).find_by(user_id:)
      end

      # A save touches the same day several times over (validation, then the
      # contract, then the service); a request-scoped memo keeps that to one
      # query without ever outliving the request that asked.
      def cache
        RequestStore.store[:worklogs_period_lock] ||= Cache.new
      end
    end

    class Cache
      def initialize
        @values = {}
      end

      def fetch(key)
        return @values[key] if @values.key?(key)

        @values[key] = yield
      end
    end
  end
end
