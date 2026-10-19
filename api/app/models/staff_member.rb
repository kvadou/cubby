class StaffMember < ApplicationRecord
  ROLES = %w[director lead_teacher assistant_teacher floater].freeze

  belongs_to :center
  has_many :staff_shifts, dependent: :destroy

  enum :role, ROLES.index_with(&:itself), validate: true
  validates :name, presence: true
end
