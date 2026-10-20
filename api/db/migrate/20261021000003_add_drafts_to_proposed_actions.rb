class AddDraftsToProposedActions < ActiveRecord::Migration[8.1]
  def change
    change_table :proposed_actions, bulk: true do |t|
      t.string :draft_status, null: false, default: "none"
      t.string :draft_model
      t.jsonb :draft_citations, null: false, default: []
      t.jsonb :draft_checks, null: false, default: {}
      t.text :draft_error
      t.integer :draft_input_tokens
      t.integer :draft_output_tokens
      # Cost in millionths of a dollar, so a cent-scale call is still an integer.
      t.bigint :draft_cost_micros
      t.datetime :drafted_at
    end
    add_check_constraint :proposed_actions, "draft_status IN ('none', 'pending', 'ready', 'failed')", name: "draft_status"

    create_table :eval_runs do |t|
      t.string :suite, null: false
      t.string :mode, null: false
      t.string :model, null: false
      t.string :judge_model
      t.integer :cases_total, null: false
      t.integer :checks_passed, null: false
      t.integer :checks_total, null: false
      t.decimal :judge_score, precision: 3, scale: 2
      t.jsonb :results, null: false, default: []
      t.datetime :created_at, null: false
    end
    add_check_constraint :eval_runs, "mode IN ('recorded', 'live')", name: "eval_mode"
    add_index :eval_runs, %i[suite created_at]
  end
end
