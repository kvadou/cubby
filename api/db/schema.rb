# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_21_000005) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "attendances", force: :cascade do |t|
    t.bigint "child_id", null: false
    t.bigint "classroom_id", null: false
    t.date "on", null: false
    t.datetime "checked_in_at", null: false
    t.datetime "checked_out_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["child_id", "on"], name: "index_attendances_on_child_id_and_on", unique: true
    t.index ["child_id"], name: "index_attendances_on_child_id"
    t.index ["classroom_id", "on"], name: "index_attendances_on_classroom_id_and_on"
    t.index ["classroom_id"], name: "index_attendances_on_classroom_id"
  end

  create_table "centers", force: :cascade do |t|
    t.string "name", null: false
    t.string "city", null: false
    t.string "timezone", default: "America/Chicago", null: false
    t.string "director_name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "children", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.date "birthdate", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_children_on_family_id"
  end

  create_table "classrooms", force: :cascade do |t|
    t.bigint "center_id", null: false
    t.string "name", null: false
    t.integer "age_min_months", null: false
    t.integer "age_max_months", null: false
    t.integer "capacity", null: false
    t.integer "ratio", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id", "name"], name: "index_classrooms_on_center_id_and_name", unique: true
    t.index ["center_id"], name: "index_classrooms_on_center_id"
    t.check_constraint "age_min_months < age_max_months", name: "classroom_age_range"
    t.check_constraint "capacity > 0 AND ratio > 0", name: "classroom_positive_limits"
  end

  create_table "domain_events", force: :cascade do |t|
    t.uuid "event_id", null: false
    t.string "event_type", null: false
    t.bigint "center_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "received_at", null: false
    t.index ["center_id", "occurred_at"], name: "index_domain_events_on_center_id_and_occurred_at"
    t.index ["event_id"], name: "index_domain_events_on_event_id", unique: true
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "child_id", null: false
    t.bigint "classroom_id"
    t.string "status", null: false
    t.date "requested_start_on"
    t.datetime "waitlisted_at"
    t.date "enrolled_on"
    t.date "withdrawn_on"
    t.datetime "last_contacted_at"
    t.string "schedule_days", default: ["mon", "tue", "wed", "thu", "fri"], null: false, array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["child_id"], name: "index_enrollments_on_child_id"
    t.index ["child_id"], name: "one_active_enrollment_per_child", unique: true, where: "((status)::text = ANY ((ARRAY['waitlisted'::character varying, 'enrolled'::character varying])::text[]))"
    t.index ["classroom_id", "status"], name: "index_enrollments_on_classroom_id_and_status"
    t.index ["classroom_id"], name: "index_enrollments_on_classroom_id"
    t.check_constraint "status::text <> 'enrolled'::text OR classroom_id IS NOT NULL", name: "enrolled_needs_classroom"
    t.check_constraint "status::text = ANY (ARRAY['waitlisted'::character varying, 'enrolled'::character varying, 'withdrawn'::character varying]::text[])", name: "enrollment_status"
  end

  create_table "eval_runs", force: :cascade do |t|
    t.string "suite", null: false
    t.string "mode", null: false
    t.string "model", null: false
    t.string "judge_model"
    t.integer "cases_total", null: false
    t.integer "checks_passed", null: false
    t.integer "checks_total", null: false
    t.decimal "judge_score", precision: 3, scale: 2
    t.jsonb "results", default: [], null: false
    t.datetime "created_at", null: false
    t.index ["suite", "created_at"], name: "index_eval_runs_on_suite_and_created_at"
    t.check_constraint "mode::text = ANY (ARRAY['recorded'::character varying, 'live'::character varying]::text[])", name: "eval_mode"
  end

  create_table "families", force: :cascade do |t|
    t.bigint "center_id", null: false
    t.string "name", null: false
    t.string "primary_guardian_name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "preferred_language", default: "en", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id", "email"], name: "index_families_on_center_id_and_email", unique: true
    t.index ["center_id"], name: "index_families_on_center_id"
  end

  create_table "family_messages", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.bigint "center_id", null: false
    t.bigint "proposed_action_id"
    t.string "subject", null: false
    t.text "body", null: false
    t.datetime "sent_at", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id"], name: "index_family_messages_on_center_id"
    t.index ["family_id", "sent_at"], name: "index_family_messages_on_family_id_and_sent_at"
    t.index ["family_id"], name: "index_family_messages_on_family_id"
    t.index ["proposed_action_id"], name: "index_family_messages_on_proposed_action_id", unique: true
  end

  create_table "guardianships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "family_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_guardianships_on_family_id"
    t.index ["user_id", "family_id"], name: "index_guardianships_on_user_id_and_family_id", unique: true
    t.index ["user_id"], name: "index_guardianships_on_user_id"
    t.index ["user_id"], name: "index_guardianships_one_family_per_user", unique: true
  end

  create_table "invoices", force: :cascade do |t|
    t.bigint "family_id", null: false
    t.string "number", null: false
    t.integer "amount_cents", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.date "due_on", null: false
    t.string "status", default: "open", null: false
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["family_id"], name: "index_invoices_on_family_id"
    t.index ["number"], name: "index_invoices_on_number", unique: true
    t.index ["status", "due_on"], name: "index_invoices_on_status_and_due_on"
    t.check_constraint "amount_cents > 0", name: "invoice_positive_amount"
    t.check_constraint "status::text <> 'paid'::text OR paid_at IS NOT NULL", name: "paid_needs_paid_at"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying, 'paid'::character varying, 'void'::character varying]::text[])", name: "invoice_status"
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "center_id", null: false
    t.string "role", default: "director", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id"], name: "index_memberships_on_center_id"
    t.index ["user_id", "center_id"], name: "index_memberships_on_user_id_and_center_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
    t.check_constraint "role::text = 'director'::text", name: "membership_role"
  end

  create_table "outbox_events", force: :cascade do |t|
    t.uuid "event_id", default: -> { "gen_random_uuid()" }, null: false
    t.string "event_type", null: false
    t.bigint "center_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "published_at"
    t.integer "attempts", default: 0, null: false
    t.text "last_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id"], name: "index_outbox_events_on_center_id"
    t.index ["event_id"], name: "index_outbox_events_on_event_id", unique: true
    t.index ["id"], name: "unpublished_outbox_events", where: "(published_at IS NULL)"
  end

  create_table "policy_chunks", force: :cascade do |t|
    t.bigint "policy_document_id", null: false
    t.bigint "center_id", null: false
    t.integer "position", null: false
    t.string "heading", null: false
    t.text "body", null: false
    t.vector "embedding", limit: 1024
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id"], name: "index_policy_chunks_on_center_id"
    t.index ["embedding"], name: "index_policy_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["policy_document_id", "position"], name: "index_policy_chunks_on_policy_document_id_and_position", unique: true
    t.index ["policy_document_id"], name: "index_policy_chunks_on_policy_document_id"
  end

  create_table "policy_documents", force: :cascade do |t|
    t.bigint "center_id", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "body_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id", "title"], name: "index_policy_documents_on_center_id_and_title", unique: true
    t.index ["center_id"], name: "index_policy_documents_on_center_id"
  end

  create_table "proposed_action_transitions", force: :cascade do |t|
    t.bigint "proposed_action_id", null: false
    t.string "from_status"
    t.string "to_status", null: false
    t.string "resolution"
    t.string "actor", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.index ["proposed_action_id"], name: "index_proposed_action_transitions_on_proposed_action_id"
  end

  create_table "proposed_actions", force: :cascade do |t|
    t.bigint "center_id", null: false
    t.string "kind", null: false
    t.string "subject_type", null: false
    t.bigint "subject_id", null: false
    t.string "dedupe_key", null: false
    t.string "status", default: "proposed", null: false
    t.string "resolution"
    t.text "rationale", null: false
    t.jsonb "facts", default: {}, null: false
    t.string "facts_digest", null: false
    t.integer "detector_version", null: false
    t.date "occurs_on"
    t.datetime "detected_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "snoozed_until"
    t.datetime "suppressed_until"
    t.datetime "decided_at"
    t.string "decided_by"
    t.text "dismiss_reason"
    t.string "draft_subject"
    t.text "draft_body"
    t.text "final_body"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "draft_status", default: "none", null: false
    t.string "draft_model"
    t.jsonb "draft_citations", default: [], null: false
    t.jsonb "draft_checks", default: {}, null: false
    t.text "draft_error"
    t.integer "draft_input_tokens"
    t.integer "draft_output_tokens"
    t.bigint "draft_cost_micros"
    t.datetime "drafted_at"
    t.index ["center_id", "status"], name: "index_proposed_actions_on_center_id_and_status"
    t.index ["center_id"], name: "index_proposed_actions_on_center_id"
    t.index ["dedupe_key", "suppressed_until"], name: "index_proposed_actions_on_dedupe_key_and_suppressed_until"
    t.index ["dedupe_key"], name: "one_open_action_per_key", unique: true, where: "((status)::text = 'proposed'::text)"
    t.index ["subject_type", "subject_id"], name: "index_proposed_actions_on_subject"
    t.check_constraint "(status::text = 'resolved'::text) = (resolution IS NOT NULL)", name: "resolution_only_when_resolved"
    t.check_constraint "draft_status::text = ANY (ARRAY['none'::character varying, 'pending'::character varying, 'ready'::character varying, 'failed'::character varying]::text[])", name: "draft_status"
    t.check_constraint "kind::text = ANY (ARRAY['stale_waitlist'::character varying, 'past_due_invoice'::character varying, 'ratio_risk'::character varying]::text[])", name: "proposed_action_kind"
    t.check_constraint "resolution IS NULL OR (resolution::text = ANY (ARRAY['condition_cleared'::character varying, 'superseded'::character varying, 'expired'::character varying]::text[]))", name: "proposed_action_resolution"
    t.check_constraint "status::text = ANY (ARRAY['proposed'::character varying, 'approved'::character varying, 'dismissed'::character varying, 'resolved'::character varying]::text[])", name: "proposed_action_status"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "kind", null: false
    t.string "token_digest"
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
    t.check_constraint "(kind::text = 'bearer'::text) = (token_digest IS NOT NULL)", name: "bearer_has_digest"
    t.check_constraint "kind::text = ANY (ARRAY['cookie'::character varying, 'bearer'::character varying]::text[])", name: "session_kind"
  end

  create_table "staff_members", force: :cascade do |t|
    t.bigint "center_id", null: false
    t.string "name", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["center_id"], name: "index_staff_members_on_center_id"
    t.check_constraint "role::text = ANY (ARRAY['director'::character varying, 'lead_teacher'::character varying, 'assistant_teacher'::character varying, 'floater'::character varying]::text[])", name: "staff_role"
  end

  create_table "staff_shifts", force: :cascade do |t|
    t.bigint "staff_member_id", null: false
    t.bigint "classroom_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["classroom_id", "starts_at"], name: "index_staff_shifts_on_classroom_id_and_starts_at"
    t.index ["classroom_id"], name: "index_staff_shifts_on_classroom_id"
    t.index ["staff_member_id"], name: "index_staff_shifts_on_staff_member_id"
    t.check_constraint "ends_at > starts_at", name: "shift_ends_after_start"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "attendances", "children"
  add_foreign_key "attendances", "classrooms"
  add_foreign_key "children", "families"
  add_foreign_key "classrooms", "centers"
  add_foreign_key "enrollments", "children"
  add_foreign_key "enrollments", "classrooms"
  add_foreign_key "families", "centers"
  add_foreign_key "family_messages", "centers"
  add_foreign_key "family_messages", "families"
  add_foreign_key "family_messages", "proposed_actions"
  add_foreign_key "guardianships", "families"
  add_foreign_key "guardianships", "users"
  add_foreign_key "invoices", "families"
  add_foreign_key "memberships", "centers"
  add_foreign_key "memberships", "users"
  add_foreign_key "outbox_events", "centers"
  add_foreign_key "policy_chunks", "centers"
  add_foreign_key "policy_chunks", "policy_documents"
  add_foreign_key "policy_documents", "centers"
  add_foreign_key "proposed_action_transitions", "proposed_actions"
  add_foreign_key "proposed_actions", "centers"
  add_foreign_key "sessions", "users"
  add_foreign_key "staff_members", "centers"
  add_foreign_key "staff_shifts", "classrooms"
  add_foreign_key "staff_shifts", "staff_members"
end
