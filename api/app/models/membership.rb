class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :center

  validates :role, inclusion: { in: %w[director] }
  validates :center_id, uniqueness: { scope: :user_id }
end
