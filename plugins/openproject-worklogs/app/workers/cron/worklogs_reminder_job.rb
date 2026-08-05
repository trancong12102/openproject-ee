module Cron
  # Monday morning: mail everybody who did not finish filling in last week.
  #
  # The schedule is fixed at boot because GoodJob reads its cron table once;
  # whether anything is actually sent is a setting, checked here at run time so
  # turning reminders off does not need a restart.
  class WorklogsReminderJob < ApplicationJob
    def perform
      unless ::Worklogs::ReminderService.enabled?
        Rails.logger.info { "[worklogs] reminders are switched off; nothing sent." }
        return
      end

      outcome = ::Worklogs::ReminderService.new.call

      Rails.logger.info do
        "[worklogs] week of #{outcome.week.start_date}: #{outcome.sent} reminders sent, #{outcome.skipped} failed."
      end
    end
  end
end
