class Enrollment < ApplicationRecord
  STATUSES = %w[waitlisted enrolled withdrawn].freeze
  DAYS = %w[mon tue wed thu fri].freeze

  belongs_to :child
  belongs_to :classroom, optional: true

  enum :status, STATUSES.index_with(&:itself), validate: true

  scope :active, -> { where(status: %w[waitlisted enrolled]) }

  validates :classroom, presence: true, if: :enrolled?
  validates :waitlisted_at, presence: true, if: :waitlisted?
  validate :schedule_days_are_weekdays
  validate :one_active_enrollment_per_child, if: -> { waitlisted? || enrolled? }

  def days_on_waitlist(now = Time.current)
    return 0 unless waitlisted_at
    ((now - waitlisted_at) / 1.day).floor
  end

  private

  def schedule_days_are_weekdays
    invalid = Array(schedule_days) - DAYS
    errors.add(:schedule_days, "contains invalid days: #{invalid.join(', ')}") if invalid.any?
    errors.add(:schedule_days, "can't be empty") if Array(schedule_days).empty?
  end

  def one_active_enrollment_per_child
    others = Enrollment.active.where(child_id: child_id).where.not(id: id)
    errors.add(:child, "already has an active enrollment") if others.exists?
  end
end
