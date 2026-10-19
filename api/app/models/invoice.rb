class Invoice < ApplicationRecord
  STATUSES = %w[open paid void].freeze

  belongs_to :family

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :number, presence: true, uniqueness: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :period_start, :period_end, :due_on, presence: true
  validates :paid_at, presence: true, if: :paid?

  scope :past_due, ->(as_of = Date.current) { open.where(due_on: ...as_of) }

  def amount
    amount_cents / 100.0
  end

  def days_past_due(as_of = Date.current)
    return 0 unless open? && due_on < as_of
    (as_of - due_on).to_i
  end
end
