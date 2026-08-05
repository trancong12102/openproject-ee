module Worklogs
  # A row the user put on a week's grid before logging anything into it, so
  # "add row" and "copy last week" survive a page reload. Pins are cleaned up
  # once the week they belong to is far in the past.
  class RowPin < ApplicationRecord
    self.table_name = "worklogs_row_pins"

    belongs_to :user
    belongs_to :entity, polymorphic: true
    belongs_to :activity, class_name: "TimeEntryActivity", optional: true

    validates :week_start, presence: true
    validates :entity_type, inclusion: { in: TimeEntry::ALLOWED_ENTITY_TYPES }
    validates :entity_id, uniqueness: { scope: %i[user_id week_start entity_type activity_id] }

    scope :stale, ->(before) { where(week_start: ...before) }
  end
end
