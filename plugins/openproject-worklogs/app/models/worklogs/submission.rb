module Worklogs
  # One person's week, handed in.
  #
  # The absence of a row means "still open" — a draft is not a record of
  # anything, and creating one for every week of every user would be a table
  # full of nothing. A row appears the moment the week is submitted, and from
  # then on it carries what happened to it.
  class Submission < ApplicationRecord
    self.table_name = "worklogs_submissions"

    # Four ways a week can be open and two ways it can be closed. Withdrawn,
    # rejected and reopened all leave the week editable, but they are not the
    # same event and a trail that called them all "rejected" would be lying by
    # omission six months later.
    STATUSES = %w[submitted approved rejected withdrawn reopened].freeze
    LOCKED_STATUSES = %w[submitted approved].freeze

    belongs_to :user
    belongs_to :submitted_by, class_name: "User", optional: true
    belongs_to :decided_by, class_name: "User", optional: true
    has_many :events, -> { order(created_at: :asc, id: :asc) },
             class_name: "Worklogs::SubmissionEvent", dependent: :delete_all,
             foreign_key: :submission_id, inverse_of: :submission

    validates :period_start, :period_end, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :user_id, uniqueness: { scope: :period_start }

    scope :pending, -> { where(status: "submitted") }
    scope :locked, -> { where(status: LOCKED_STATUSES) }
    scope :covering, ->(date) { where(period_start: ..date).where(period_end: date..) }
    scope :for_period, ->(start_date) { where(period_start: start_date) }

    def locked?
      LOCKED_STATUSES.include?(status)
    end

    def submitted? = status == "submitted"
    def approved? = status == "approved"
    def open? = !locked?

    def status_label
      I18n.t("worklogs.approval.statuses.#{status}")
    end

    def week
      @week ||= Week.new(period_start)
    end

    # Self-approval is refused for everyone but administrators, unless an
    # administrator has turned it on for the instance. A two-person team still
    # has to be able to close a week, but on any larger instance nobody should
    # be able to sign off their own timesheet by accident.
    def decidable_by?(actor)
      return false unless submitted?
      return false unless actor&.allowed_globally?(:approve_worklogs)

      actor.id != user_id || actor.admin? || Settings.allow_self_approval?
    end

    def withdrawable_by?(actor)
      submitted? && (actor&.id == user_id || actor&.admin?)
    end

    # Reopening an approved week is an approver's act, not the owner's: it is
    # the only thing that can unlock time somebody else has already signed off.
    def reopenable_by?(actor)
      approved? && actor&.allowed_globally?(:approve_worklogs)
    end
  end
end
