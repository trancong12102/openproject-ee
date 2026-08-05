module Worklogs
  # A name pinned to a report definition.
  #
  # Because a report is a URL, this stores no results and no data — only the
  # parameters. Opening someone else's shared report runs the same query the
  # opener would have built by hand, against their own visible time entries, so
  # sharing a report shares a question and never an answer.
  class SavedReport < ApplicationRecord
    self.table_name = "worklogs_saved_reports"

    belongs_to :user

    validates :name, presence: true, length: { maximum: 255 }
    validates :name, uniqueness: { scope: :user_id, case_sensitive: false }

    scope :visible, ->(user) { where(user_id: user.id).or(where(shared: true)) }
    scope :ordered, -> { order(Arel.sql("LOWER(name)")) }

    def query
      Reports::Query.from_params((query_params || {}).symbolize_keys)
    end

    # Stored normalised rather than as the raw request, so two reports built by
    # different routes to the same place compare equal.
    def query=(value)
      self.query_params = value.definition_params
    end

    def matches?(other_query)
      query.definition_params == other_query.definition_params
    end

    def owned_by?(other)
      other.present? && user_id == other.id
    end

    def editable_by?(other)
      owned_by?(other) || other&.admin?
    end
  end
end
