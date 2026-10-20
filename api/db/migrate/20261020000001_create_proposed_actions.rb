# Action queue (prior-art record D2-D8, D16). A detector finds work, writes one row per open
# condition, and a human closes it. Closed rows are never reopened; a recurring condition gets a new row.
class CreateProposedActions < ActiveRecord::Migration[8.1]
  def change
    create_table :proposed_actions do |t|
      t.references :center, null: false, foreign_key: true
      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: false
      # Condition identity computed by the detector, e.g. "ratio_risk:classroom:3:2026-10-20".
      t.string :dedupe_key, null: false
      t.string :status, null: false, default: "proposed"
      t.string :resolution
      t.text :rationale, null: false
      # Minimal snapshot of what the detector saw. Never changed after insert; no contact details.
      t.jsonb :facts, null: false, default: {}
      t.string :facts_digest, null: false
      t.integer :detector_version, null: false
      t.date :occurs_on
      t.datetime :detected_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :snoozed_until
      t.datetime :suppressed_until
      t.datetime :decided_at
      t.string :decided_by
      t.text :dismiss_reason
      # Filled in phase 4 (Bedrock draft) and at approval (what the director actually sends).
      t.string :draft_subject
      t.text :draft_body
      t.text :final_body
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :proposed_actions, :dedupe_key, unique: true, where: "status = 'proposed'",
              name: "one_open_action_per_key"
    add_index :proposed_actions, %i[center_id status]
    add_index :proposed_actions, %i[dedupe_key suppressed_until]

    add_check_constraint :proposed_actions, "kind IN ('stale_waitlist','past_due_invoice','ratio_risk')",
                         name: "proposed_action_kind"
    add_check_constraint :proposed_actions, "status IN ('proposed','approved','dismissed','resolved')",
                         name: "proposed_action_status"
    add_check_constraint :proposed_actions,
                         "resolution IS NULL OR resolution IN ('condition_cleared','superseded','expired')",
                         name: "proposed_action_resolution"
    add_check_constraint :proposed_actions, "(status = 'resolved') = (resolution IS NOT NULL)",
                         name: "resolution_only_when_resolved"

    # Append-only history, written in the same transaction as every status change (D7).
    create_table :proposed_action_transitions do |t|
      t.references :proposed_action, null: false, foreign_key: true
      t.string :from_status
      t.string :to_status, null: false
      t.string :resolution
      t.string :actor, null: false
      t.text :note
      t.datetime :created_at, null: false
    end
  end
end
