class Classroom < ApplicationRecord
  belongs_to :center
  has_many :enrollments, dependent: :restrict_with_error
  has_many :staff_shifts, dependent: :destroy
  has_many :attendances, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :center_id }
  validates :age_min_months, :age_max_months, :capacity, :ratio,
            presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :capacity, :ratio, numericality: { greater_than: 0 }
  validate :age_range_is_ordered

  def enrolled_count
    enrollments.enrolled.count
  end

  def open_seats
    [ capacity - enrolled_count, 0 ].max
  end

  def accepts_age?(months)
    months >= age_min_months && months < age_max_months
  end

  # Children scheduled to attend on a given date, based on enrollment schedule days.
  def expected_children_on(date)
    day = date.strftime("%a").downcase
    enrollments.enrolled.where("? = ANY(schedule_days)", day).count
  end

  def staff_required_for(children_count)
    (children_count.to_f / ratio).ceil
  end

  private

  def age_range_is_ordered
    return if age_min_months.blank? || age_max_months.blank?
    errors.add(:age_max_months, "must be greater than the minimum age") unless age_max_months > age_min_months
  end
end
