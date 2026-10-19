class CreateEnrollments < ActiveRecord::Migration[8.1]
  def change
    create_table :enrollments do |t|
      t.references :child, null: false, foreign_key: true
      t.references :classroom, foreign_key: true
      t.string :status, null: false
      t.date :requested_start_on
      t.datetime :waitlisted_at
      t.date :enrolled_on
      t.date :withdrawn_on
      t.datetime :last_contacted_at
      # Weekdays the child attends, e.g. {mon,tue,wed,thu,fri}.
      t.string :schedule_days, array: true, null: false, default: %w[mon tue wed thu fri]
      t.timestamps
    end
    add_check_constraint :enrollments, "status IN ('waitlisted','enrolled','withdrawn')", name: "enrollment_status"
    add_check_constraint :enrollments, "status <> 'enrolled' OR classroom_id IS NOT NULL", name: "enrolled_needs_classroom"
    # A child has at most one active (waitlisted or enrolled) enrollment.
    add_index :enrollments, :child_id, unique: true, where: "status IN ('waitlisted','enrolled')",
              name: "one_active_enrollment_per_child"
    add_index :enrollments, %i[classroom_id status]
  end
end
