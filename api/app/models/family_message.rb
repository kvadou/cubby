# A message a center sent a family: written when a director approves a family-facing action, or an
# announcement. Parents read these in the mobile app.
class FamilyMessage < ApplicationRecord
  belongs_to :family
  belongs_to :center
  belongs_to :proposed_action, optional: true

  validates :subject, :body, :sent_at, presence: true
  validate :family_belongs_to_center

  scope :unread, -> { where(read_at: nil) }

  private

  def family_belongs_to_center
    errors.add(:family, "must belong to the message's center") if family && family.center_id != center_id
  end
end
