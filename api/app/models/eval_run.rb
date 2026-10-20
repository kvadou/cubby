class EvalRun < ApplicationRecord
  validates :suite, :mode, :model, :cases_total, :checks_passed, :checks_total, presence: true
  validates :mode, inclusion: { in: %w[recorded live] }
end
