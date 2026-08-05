module Worklogs
  # Every switch this plugin has, in one typed place.
  #
  # `Setting.plugin_openproject_worklogs` is a bare hash whose values arrive
  # from an HTML form as strings, so nothing else in the plugin should have to
  # remember that "0" is false and that a blank tolerance is not zero hours.
  class Settings
    KEY = :plugin_openproject_worklogs

    # Defined outside `app/` because the engine has to read them before
    # Zeitwerk exists. See OpenProject::Worklogs::SETTINGS_DEFAULTS in
    # lib/open_project/worklogs/engine.rb.
    DEFAULTS = OpenProject::Worklogs::SETTINGS_DEFAULTS

    BOOLEANS = %w[approvals_enabled lock_approved_periods allow_self_approval reminders_enabled].freeze
    WEEKDAYS = (1..7).to_a.freeze
    HOURS = (0..23).to_a.freeze

    class << self
      # Read once per request. These are consulted on every contract validation
      # and every cell of the grid, and `Setting` reads hit the cache but still
      # marshal the hash each time.
      def current
        return new(raw) unless defined?(RequestStore) && RequestStore.active?

        RequestStore.store[:worklogs_settings] ||= new(raw)
      end

      def raw
        value = Setting.send(KEY)
        value.is_a?(Hash) ? value : {}
      end

      # After a write, so the rest of the request sees what was just saved.
      def invalidate!
        RequestStore.delete(:worklogs_settings) if defined?(RequestStore) && RequestStore.active?
      end

      def method_missing(name, *args, &)
        return current.public_send(name, *args, &) if current.respond_to?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        DEFAULTS.key?(name.to_s.delete_suffix("?")) || super
      end

      # Everything the admin form is allowed to write, cast on the way in so a
      # bad value never reaches the database.
      def sanitise(params)
        DEFAULTS.keys.index_with do |key|
          value = params[key]

          case key
          when *BOOLEANS then boolean(value)
          when "reminder_weekday" then within(value.to_i, WEEKDAYS, DEFAULTS[key])
          when "reminder_hour" then within(value.to_i, HOURS, DEFAULTS[key])
          when "reminder_tolerance" then [value.to_f.round(2), 0].max
          else value
          end
        end
      end

      private

      def boolean(value)
        ActiveModel::Type::Boolean.new.cast(value).present?
      end

      def within(value, allowed, fallback)
        allowed.include?(value) ? value : fallback
      end
    end

    def initialize(values)
      @values = DEFAULTS.merge(values.to_h.stringify_keys)
    end

    def approvals_enabled?
      boolean("approvals_enabled")
    end

    # Approval without locking is a real way to work: some teams want the
    # sign-off recorded and still want a correction to be possible afterwards.
    def lock_approved_periods?
      approvals_enabled? && boolean("lock_approved_periods")
    end

    def allow_self_approval?
      boolean("allow_self_approval")
    end

    def reminders_enabled?
      boolean("reminders_enabled")
    end

    def reminder_weekday
      @values["reminder_weekday"].to_i
    end

    def reminder_hour
      @values["reminder_hour"].to_i
    end

    def reminder_tolerance
      @values["reminder_tolerance"].to_f
    end

    def to_h
      @values.dup
    end

    def [](key)
      @values[key.to_s]
    end

    private

    def boolean(key)
      ActiveModel::Type::Boolean.new.cast(@values[key]).present?
    end
  end
end
