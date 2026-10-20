class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    # Transactional outbox: written in the same transaction as the change it describes, published to
    # SNS afterwards (docs/prior-art/2026-10-19-phase5-events.md, D1, D2).
    create_table :outbox_events do |t|
      t.uuid :event_id, null: false, default: -> { "gen_random_uuid()" }
      t.string :event_type, null: false
      t.references :center, null: false, foreign_key: true
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :published_at
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.timestamps
    end
    add_index :outbox_events, :event_id, unique: true
    add_index :outbox_events, :id, where: "published_at IS NULL", name: "unpublished_outbox_events"

    # What the analytics consumer has received. event_id makes redelivery a no-op (D4).
    create_table :domain_events do |t|
      t.uuid :event_id, null: false
      t.string :event_type, null: false
      t.bigint :center_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :received_at, null: false
    end
    add_index :domain_events, :event_id, unique: true
    add_index :domain_events, %i[center_id occurred_at]
  end
end
