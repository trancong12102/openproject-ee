module Worklogs
  module Timesheets
    # What you are about to hand in, before you hand it in.
    #
    # The figures are repeated here on purpose: submitting is the moment to
    # notice that Thursday is empty, and the dialog is the last screen anybody
    # reads before the week locks.
    class SubmitFormComponent < ApplicationComponent
      include OpTurbo::Streamable
      include ApplicationHelper
      include OpPrimer::ComponentHelpers
      include Worklogs::TimesheetHelper

      FORM_ID = "worklogs-submit-form".freeze

      options :submission, :week, :user, :timesheet

      def form_id
        FORM_ID
      end

      def form_options
        { url: worklogs_submission_path(date: week.to_param, user_id: user.id), method: :post }
      end

      def errors
        submission.errors.full_messages
      end

      def logged
        worklogs_duration(timesheet.total)
      end

      def capacity
        worklogs_duration(timesheet.capacity.total)
      end

      def difference
        (timesheet.total - timesheet.capacity.total).round(2)
      end

      def difference_label
        return I18n.t("worklogs.approval.on_target") if difference.zero?

        key = difference.negative? ? "short_by" : "over_by"
        I18n.t("worklogs.approval.#{key}", hours: worklogs_duration(difference.abs))
      end

      def difference_scheme
        return "-ok" if difference.zero?

        difference.negative? ? "-short" : "-over"
      end

      # Days inside the week that are working days and still have nothing on
      # them. The single most common reason a week comes back rejected.
      def empty_days
        @empty_days ||= week.dates.select do |date|
          timesheet.capacity.hours_for(date).positive? && timesheet.daily_total(date).zero?
        end
      end

      def empty_days_label
        I18n.t("worklogs.approval.empty_days",
               count: empty_days.size,
               days: empty_days.map { |date| worklogs_day_name(date) }.join(", "))
      end

      def resubmission?
        submission.persisted?
      end
    end
  end
end
