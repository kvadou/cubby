class CreateUsersAndSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.timestamps
    end
    add_index :users, :email_address, unique: true

    # One row per signed-in device. Web sessions are found by id from a signed cookie; mobile
    # sessions by the SHA-256 digest of a bearer token that is never stored in the clear.
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :token_digest
      t.string :ip_address
      t.string :user_agent
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true
    add_check_constraint :sessions, "kind IN ('cookie', 'bearer')", name: "session_kind"
    add_check_constraint :sessions, "(kind = 'bearer') = (token_digest IS NOT NULL)", name: "bearer_has_digest"

    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :center, null: false, foreign_key: true
      t.string :role, null: false, default: "director"
      t.timestamps
    end
    add_index :memberships, %i[user_id center_id], unique: true
    add_check_constraint :memberships, "role IN ('director')", name: "membership_role"
  end
end
