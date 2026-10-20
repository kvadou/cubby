class PolicyDocument < ApplicationRecord
  belongs_to :center
  has_many :chunks, -> { order(:position) }, class_name: "PolicyChunk", dependent: :destroy

  validates :title, :body, :body_digest, presence: true
  before_validation { self.body_digest = Digest::SHA256.hexdigest(body.to_s) }
end
