class CreateWorklogsRowPins < ActiveRecord::Migration[8.1]
  def change
    create_table :worklogs_row_pins do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.date :week_start, null: false
      t.references :entity, polymorphic: true, null: false, index: false
      t.references :activity, null: true, foreign_key: { to_table: :enumerations }, index: false

      t.timestamps
    end

    add_index :worklogs_row_pins,
              %i[user_id week_start entity_type entity_id activity_id],
              unique: true,
              name: "index_worklogs_row_pins_uniqueness"
  end
end
