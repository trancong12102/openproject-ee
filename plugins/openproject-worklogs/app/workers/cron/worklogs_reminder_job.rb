module Cron
  # Mail everybody who did not finish filling in last week.
  #
  # Scheduled hourly rather than weekly on purpose: GoodJob reads its cron table
  # once, at boot, so a weekly entry would freeze the day and hour into the
  # deployment. Running every hour and checking the setting here means an
  # administrator can move the reminder to Friday afternoon without a restart —
  # and 167 of the 168 runs a week do nothing but read one setting.
  class WorklogsReminderJob < ApplicationJob
    def perform(force: false)
      return unless force || due?

      outcome = ::Worklogs::ReminderService.new.call

      Rails.logger.info do
        "[worklogs] week of #{outcome.week.start_date}: #{outcome.sent} reminders sent, #{outcome.skipped} failed."
      end
    end

    private

    def due?
      return false unless ::Worklogs::ReminderService.enabled?

      settings = ::Worklogs::Settings.current
      now = Time.zone.now

      now.to_date.cwday == settings.reminder_weekday && now.hour == settings.reminder_hour
    end
  end
end
