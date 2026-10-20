class Family < ApplicationRecord
  belongs_to :center
  has_many :children, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :guardianships, dependent: :destroy
  has_many :messages, class_name: "FamilyMessage", dependent: :destroy

  validates :name, :primary_guardian_name, :email, presence: true
  validates :email, uniqueness: { scope: :center_id, case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }

  def guardian_first_name
    primary_guardian_name.split.first
  end
end
