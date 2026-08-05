module Worklogs
  module Reports
    # The entries behind one figure in the pivot.
    #
    # Read-only on purpose: editing here would need the full time entry form,
    # which core already has and which the timesheet already links to. This
    # answers "which entries add up to that number", and hands each one over.
    class EntriesDialogComponent < ApplicationComponent
      include OpTurbo::Streamable
      include ApplicationHelper
      include OpPrimer::ComponentHelpers
      include Worklogs::ReportsHelper

      DIALOG_ID = "worklogs-entries-dialog".freeze
      LIMIT = 100

      options :entries, :count, :title, :query, :costs_visible

      def dialog_id
        DIALOG_ID
      end

      def visible_entries
        entries.first(LIMIT)
      end

      def truncated?
        count > LIMIT
      end

      def truncation_note
        I18n.t("worklogs.reports.entries_truncated", shown: LIMIT, total: count)
      end

      def subtitle
        I18n.t("worklogs.reports.entries_subtitle", count:, hours: worklogs_duration(total_hours))
      end

      def total_hours
        entries.sum { |entry| entry.hours.to_f }
      end

      def entry_path(entry)
        return nil unless entry.entity.is_a?(WorkPackage)

        work_package_path(entry.entity)
      end

      def entry_subject(entry)
        entry.entity.respond_to?(:subject) ? entry.entity.subject : entry.entity&.to_s
      end

      def entry_reference(entry)
        return nil unless entry.entity.is_a?(WorkPackage)

        "#{entry.entity.type&.name} ##{entry.entity.id}"
      end

      def entry_costs(entry)
        worklogs_currency(entry.overridden_costs || entry.costs || 0)
      end

      def edit_path(entry)
        dialog_time_entry_path(entry) if entry.editable_by?(User.current)
      end
    end
  end
end
