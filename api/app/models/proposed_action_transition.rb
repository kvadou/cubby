class ProposedActionTransition < ApplicationRecord
  belongs_to :proposed_action

  validates :to_status, :actor, presence: true

  def readonly?
    persisted?
  end
end
