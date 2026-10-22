# One row per one-click demo sign-in: when, and which site sent the visitor (host only, no IP or path).
# Demo::Reset keeps this table, so visits survive the nightly reset.
class CreateDemoVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :demo_visits do |t|
      t.string :referrer_host, limit: 100
      t.datetime :created_at, null: false
      t.index :created_at
    end
  end
end
