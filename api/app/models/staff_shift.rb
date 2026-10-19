class StaffShift < ApplicationRecord
  belongs_to :staff_member
  belongs_to :classroom

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start

  scope :on_date, ->(date) { where(starts_at: date.all_day) }

  private

  def ends_after_start
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "must be after the start") unless ends_at > starts_at
  end
end
