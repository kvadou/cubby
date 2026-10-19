class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :family, null: false, foreign_key: true
      t.string :number, null: false
      t.integer :amount_cents, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.date :due_on, null: false
      t.string :status, null: false, default: "open"
      t.datetime :paid_at
      t.timestamps
    end
    add_index :invoices, :number, unique: true
    add_index :invoices, %i[status due_on]
    add_check_constraint :invoices, "status IN ('open','paid','void')", name: "invoice_status"
    add_check_constraint :invoices, "amount_cents > 0", name: "invoice_positive_amount"
    add_check_constraint :invoices, "status <> 'paid' OR paid_at IS NOT NULL", name: "paid_needs_paid_at"
  end
end
