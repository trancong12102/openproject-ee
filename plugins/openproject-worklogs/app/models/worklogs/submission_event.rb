module Worklogs
  # One line of a submission's history.
  #
  # Append-only and never updated: the point of a trail is that it says what
  # happened, including the parts somebody would rather it did not.
  class SubmissionEvent < ApplicationRecord
    self.table_name = "worklogs_submission_events"

    ACTIONS = %w[submitted withdrawn approved rejected reopened].freeze

    belongs_to :submission, class_name: "Worklogs::Submission"
    belongs_to :user

    validates :action, inclusion: { in: ACTIONS }

    def label
      I18n.t("worklogs.approval.events.#{action}")
    end
  end
end
