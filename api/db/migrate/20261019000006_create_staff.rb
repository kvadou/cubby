class CreateStaff < ActiveRecord::Migration[8.1]
  def change
    create_table :staff_members do |t|
      t.references :center, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role, null: false
      t.timestamps
    end
    add_check_constraint :staff_members, "role IN ('director','lead_teacher','assistant_teacher','floater')", name: "staff_role"

    create_table :staff_shifts do |t|
      t.references :staff_member, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end
    add_check_constraint :staff_shifts, "ends_at > starts_at", name: "shift_ends_after_start"
    add_index :staff_shifts, %i[classroom_id starts_at]
  end
end
