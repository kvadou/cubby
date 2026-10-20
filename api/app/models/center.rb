class Center < ApplicationRecord
  has_many :classrooms, dependent: :destroy
  has_many :families, dependent: :destroy
  has_many :children, through: :families
  has_many :staff_members, dependent: :destroy
  has_many :proposed_actions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :policy_documents, dependent: :destroy
  has_many :users, through: :memberships

  validates :name, :city, :timezone, :director_name, presence: true

  def today
    Time.current.in_time_zone(timezone).to_date
  end
end
