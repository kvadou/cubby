# A signed-in device. See docs/prior-art/2026-10-19-phase3-auth.md (D2).
class Session < ApplicationRecord
  LIFETIME = 30.days

  belongs_to :user

  enum :kind, { cookie: "cookie", bearer: "bearer" }, validate: true

  scope :active, ->(now = Time.current) { where("expires_at > ?", now) }

  before_validation { self.expires_at ||= LIFETIME.from_now }

  def self.digest(token) = Digest::SHA256.hexdigest(token)

  # Returns [session, raw_token]. The raw token is shown to the client once and never stored.
  def self.issue_bearer!(user:, **attrs)
    token = SecureRandom.base58(43)
    [ create!(user: user, kind: "bearer", token_digest: digest(token), **attrs), token ]
  end

  def self.find_by_bearer(token)
    active.bearer.find_by(token_digest: digest(token)) if token.present?
  end
end
