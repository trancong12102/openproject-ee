class CreateWorklogsSavedReports < ActiveRecord::Migration[8.1]
  def change
    create_table :worklogs_saved_reports do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.boolean :shared, null: false, default: false
      # The report definition, exactly as it travels in the URL. No data lives
      # here — only how to ask for it, so a shared report can never hand its
      # owner's figures to someone who may not see them.
      t.jsonb :query_params, null: false, default: {}

      t.timestamps
    end

    add_index :worklogs_saved_reports, %i[user_id name], unique: true,
              name: "index_worklogs_saved_reports_on_owner_and_name"
    add_index :worklogs_saved_reports, :shared, where: "shared"
  end
end
