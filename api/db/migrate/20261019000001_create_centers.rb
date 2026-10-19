class CreateCenters < ActiveRecord::Migration[8.1]
  def change
    create_table :centers do |t|
      t.string :name, null: false
      t.string :city, null: false
      t.string :timezone, null: false, default: "America/Chicago"
      t.string :director_name, null: false
      t.timestamps
    end
  end
end
