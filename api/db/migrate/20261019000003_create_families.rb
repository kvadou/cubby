class CreateFamilies < ActiveRecord::Migration[8.1]
  def change
    create_table :families do |t|
      t.references :center, null: false, foreign_key: true
      t.string :name, null: false
      t.string :primary_guardian_name, null: false
      t.string :email, null: false
      t.string :phone
      t.string :preferred_language, null: false, default: "en"
      t.timestamps
    end
    add_index :families, %i[center_id email], unique: true
  end
end
