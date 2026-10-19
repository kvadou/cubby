class Child < ApplicationRecord
  belongs_to :family
  has_many :enrollments, dependent: :destroy
  has_many :attendances, dependent: :destroy

  validates :first_name, :last_name, :birthdate, presence: true

  def age_in_months(on = Date.current)
    months = (on.year * 12 + on.month) - (birthdate.year * 12 + birthdate.month)
    months -= 1 if on.day < birthdate.day
    months
  end

  def active_enrollment
    enrollments.active.first
  end

  def full_name
    "#{first_name} #{last_name}"
  end
end
