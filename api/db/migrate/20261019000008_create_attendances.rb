class CreateAttendances < ActiveRecord::Migration[8.1]
  def change
    create_table :attendances do |t|
      t.references :child, null: false, foreign_key: true
      t.references :classroom, null: false, foreign_key: true
      t.date :on, null: false
      t.datetime :checked_in_at, null: false
      t.datetime :checked_out_at
      t.timestamps
    end
    add_index :attendances, %i[child_id on], unique: true
    add_index :attendances, %i[classroom_id on]
  end
end
