class CreateClassrooms < ActiveRecord::Migration[8.1]
  def change
    create_table :classrooms do |t|
      t.references :center, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :age_min_months, null: false
      t.integer :age_max_months, null: false
      t.integer :capacity, null: false
      # Children allowed per staff member on the floor.
      t.integer :ratio, null: false
      t.timestamps
    end
    add_index :classrooms, %i[center_id name], unique: true
    add_check_constraint :classrooms, "age_min_months < age_max_months", name: "classroom_age_range"
    add_check_constraint :classrooms, "capacity > 0 AND ratio > 0", name: "classroom_positive_limits"
  end
end
