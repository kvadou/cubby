class Attendance < ApplicationRecord
  belongs_to :child
  belongs_to :classroom

  validates :on, :checked_in_at, presence: true
  validates :child_id, uniqueness: { scope: :on }
end
