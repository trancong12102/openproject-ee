module Worklogs
  # Decides who is behind on a week and mails them about it.
  #
  # The whole point is the *decision*, not the sending: a reminder that goes to
  # somebody who is up to date, or who already submitted, or who was on holiday
  # all week, is the reason people filter these mails to a folder they never
  # open. So the rules are explicit and each has a reason next to it.
  class ReminderService
    Outcome = Struct.new(:week, :sent, :skipped, keyword_init: true)

    attr_reader :week, :tolerance

    def initialize(week: nil, tolerance: nil)
      @week = week || Week.current.previous
      @tolerance = (tolerance || settings["reminder_tolerance"] || 0.5).to_f
    end

    class << self
      def settings
        setting = Setting.plugin_openproject_worklogs
        setting.is_a?(Hash) ? setting.with_indifferent_access : {}.with_indifferent_access
      end

      def enabled?
        ActiveModel::Type::Boolean.new.cast(settings["reminders_enabled"]).present?
      end
    end

    def settings
      self.class.settings
    end

    def call
      sent = 0
      skipped = 0

      recipients.each do |user|
        if deliver(user) then sent += 1 else skipped += 1 end
      end

      Outcome.new(week:, sent:, skipped:)
    end

    # Everyone active who owed hours that week and did not log them, minus
    # everyone who has already handed the week in — chasing somebody who did
    # what you asked is how a reminder becomes noise.
    def recipients
      @recipients ||= begin
        users = User.active.not_builtin.where.not(mail: [nil, ""]).to_a
        submitted = Submission.where(period_start: week.start_date, status: %w[submitted approved])
                              .pluck(:user_id).to_set

        users.reject { |user| submitted.include?(user.id) }
             .select { |user| behind?(user) }
      end
    end

    private

    def calendar
      @calendar ||= CapacityCalendar.new(user_ids: User.active.not_builtin.pluck(:id), range: week.range)
    end

    def logged
      @logged ||= TimeEntry.where(spent_on: week.range)
                           .group(:user_id)
                           .sum(:hours)
                           .transform_values(&:to_f)
    end

    # A week with no capacity at all — a full week of holiday, or somebody who
    # is not on a working schedule — is not a week anybody is behind on.
    # `tolerance` keeps a rounding difference of a few minutes from generating
    # a mail nobody can act on.
    #
    # Only days that have already happened count. The cron only ever asks about
    # last week, where that makes no difference; it matters the moment somebody
    # calls this by hand for the week they are standing in.
    def behind?(user)
      capacity = calendar.total_for(user.id, elapsed_dates)
      return false if capacity.zero?

      (capacity - logged.fetch(user.id, 0.0)) > tolerance
    end

    def elapsed_dates
      @elapsed_dates ||= week.dates.select { |date| date <= Time.zone.today }
    end

    def deliver(user)
      ReminderMailer.missing_time(user, week.start_date).deliver_later
      true
    rescue StandardError => e
      Rails.logger.error { "[worklogs] reminder to user #{user.id} failed: #{e.message}" }
      false
    end
  end
end
