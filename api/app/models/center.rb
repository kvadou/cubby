class Center < ApplicationRecord
  has_many :classrooms, dependent: :destroy
  has_many :families, dependent: :destroy
  has_many :children, through: :families
  has_many :staff_members, dependent: :destroy
  has_many :proposed_actions, dependent: :destroy

  validates :name, :city, :timezone, :director_name, presence: true

  def today
    Time.current.in_time_zone(timezone).to_date
  end
end
