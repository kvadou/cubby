# Parents: a user linked to a family (not a center), and the messages a center sends a family.
class CreateFamilyAccess < ActiveRecord::Migration[8.1]
  def change
    create_table :guardianships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :family, null: false, foreign_key: true
      t.timestamps
      t.index %i[user_id family_id], unique: true
    end

    create_table :family_messages do |t|
      t.references :family, null: false, foreign_key: true
      t.references :center, null: false, foreign_key: true
      # One message per approved action; null for announcements.
      t.references :proposed_action, foreign_key: true, index: { unique: true }
      t.string :subject, null: false
      t.text :body, null: false
      t.datetime :sent_at, null: false
      t.datetime :read_at
      t.timestamps
      t.index %i[family_id sent_at]
    end
  end
end
