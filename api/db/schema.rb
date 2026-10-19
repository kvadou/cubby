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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_000008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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

  add_foreign_key "attendances", "children"
  add_foreign_key "attendances", "classrooms"
  add_foreign_key "children", "families"
  add_foreign_key "classrooms", "centers"
  add_foreign_key "enrollments", "children"
  add_foreign_key "enrollments", "classrooms"
  add_foreign_key "families", "centers"
  add_foreign_key "invoices", "families"
  add_foreign_key "staff_members", "centers"
  add_foreign_key "staff_shifts", "classrooms"
  add_foreign_key "staff_shifts", "staff_members"
end
