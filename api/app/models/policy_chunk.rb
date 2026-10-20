class PolicyChunk < ApplicationRecord
  belongs_to :policy_document
  belongs_to :center

  has_neighbors :embedding

  validates :heading, :body, :position, presence: true

  # The ID a draft uses to cite this chunk inside one prompt ("P1", "P2", ...) is assigned per prompt;
  # this label is what directors see.
  def label = "#{policy_document.title}: #{heading}"
end
