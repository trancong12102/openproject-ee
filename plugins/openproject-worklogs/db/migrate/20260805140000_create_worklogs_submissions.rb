class CreateWorklogsSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :worklogs_submissions do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.string :status, null: false, default: "submitted"

      t.references :submitted_by, null: true, foreign_key: { to_table: :users }, index: false
      t.datetime :submitted_at, null: true
      t.references :decided_by, null: true, foreign_key: { to_table: :users }, index: false
      t.datetime :decided_at, null: true

      t.text :note
      t.text :decision_note
      # What was submitted, as it stood when it was submitted. An approval that
      # cannot say how many hours it approved is not much of an approval.
      t.decimal :hours, precision: 10, scale: 2, null: false, default: 0

      t.timestamps
    end

    # One submission per person per period: a week is either open, waiting or
    # settled, never two of those at once.
    add_index :worklogs_submissions, %i[user_id period_start], unique: true,
              name: "index_worklogs_submissions_on_user_and_period"
    add_index :worklogs_submissions, %i[status period_start]

    create_table :worklogs_submission_events do |t|
      t.references :submission, null: false, index: true,
                   foreign_key: { to_table: :worklogs_submissions, on_delete: :cascade }
      t.references :user, null: false, foreign_key: true, index: false
      t.string :action, null: false
      t.text :note
      t.decimal :hours, precision: 10, scale: 2, null: false, default: 0

      t.datetime :created_at, null: false
    end
  end
end
