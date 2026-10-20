# One unit of proposed work for a director. See docs/prior-art/2026-10-19-phase2-action-queue.md.
#
# Lifecycle: proposed -> approved | dismissed | resolved. Every change goes through #transition!,
# which is a conditional UPDATE guarded by status and lock_version plus one history row, in one
# transaction. That method is also the seam where phase 5 adds the event outbox.
class ProposedAction < ApplicationRecord
  KINDS = %w[stale_waitlist past_due_invoice ratio_risk].freeze
  STATUSES = %w[proposed approved dismissed resolved].freeze
  RESOLUTIONS = %w[condition_cleared superseded expired].freeze
  # How long a closed condition stays quiet before a detector may raise it again (D5, D11 proposals).
  COOLDOWNS = { "stale_waitlist" => 14.days, "past_due_invoice" => 7.days }.freeze
  # Facts go to a language model in phase 4, so contact details never belong in them (D8).
  FORBIDDEN_FACT_KEYS = /email|phone|address/i
  EMBEDDED_EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/

  class InvalidTransition < StandardError; end

  belongs_to :center
  belongs_to :subject, polymorphic: true
  has_many :transitions, -> { order(:id) }, class_name: "ProposedActionTransition", dependent: :destroy

  enum :kind, KINDS.index_with(&:itself), validate: true
  enum :status, STATUSES.index_with(&:itself), validate: true

  attr_readonly :facts, :facts_digest, :kind, :dedupe_key

  validates :dedupe_key, :rationale, :facts_digest, :detector_version, presence: true
  validate :facts_have_no_contact_details

  scope :inbox, ->(now = Time.current) { proposed.where("snoozed_until IS NULL OR snoozed_until <= ?", now) }

  def self.digest(facts)
    Digest::SHA256.hexdigest(JSON.generate(facts.deep_stringify_keys.sort.to_h))
  end

  # Detectors skip a key while a recently closed row for it is still cooling down.
  def self.suppressed?(dedupe_key, now = Time.current)
    where(dedupe_key: dedupe_key).where.not(status: "proposed").where("suppressed_until > ?", now).exists?
  end

  def approve!(by:, final_body: nil, now: Time.current)
    transition!(to: "approved", actor: by, now: now,
                attrs: { final_body: final_body || draft_body, suppressed_until: cooldown_end(now) })
  end

  def dismiss!(by:, reason: nil, now: Time.current)
    transition!(to: "dismissed", actor: by, note: reason, now: now,
                attrs: { dismiss_reason: reason, suppressed_until: cooldown_end(now) })
  end

  def resolve!(resolution:, by: "system", now: Time.current)
    raise ArgumentError, "unknown resolution #{resolution}" unless RESOLUTIONS.include?(resolution)
    transition!(to: "resolved", actor: by, resolution: resolution, now: now, attrs: { resolution: resolution })
  end

  # Snoozing hides the row from the inbox without closing it, so it is not a status change.
  def snooze!(until_time:)
    raise InvalidTransition, "only proposed actions can be snoozed" unless proposed?
    update!(snoozed_until: until_time)
  end

  def transition!(to:, actor:, resolution: nil, note: nil, now: Time.current, attrs: {})
    raise InvalidTransition, "unknown status #{to}" unless STATUSES.include?(to)

    self.class.transaction do
      changes = attrs.merge(status: to, decided_at: now, decided_by: actor, snoozed_until: nil,
                            lock_version: lock_version + 1, updated_at: now)
      updated = self.class.where(id: id, status: "proposed", lock_version: lock_version).update_all(changes)
      raise InvalidTransition, "action #{id} is no longer proposed or was changed by someone else" if updated.zero?

      ProposedActionTransition.create!(proposed_action_id: id, from_status: status, to_status: to,
                                       resolution: resolution, actor: actor, note: note, created_at: now)
      reload
    end
  end

  private

  def cooldown_end(now)
    if ratio_risk?
      center.then { |c| ActiveSupport::TimeZone[c.timezone].local(occurs_on.year, occurs_on.month, occurs_on.day).end_of_day }
    else
      now + COOLDOWNS.fetch(kind)
    end
  end

  def facts_have_no_contact_details
    flat = facts.to_h.to_a.flatten.map(&:to_s)
    bad_key = facts.to_h.keys.find { |k| k.to_s.match?(FORBIDDEN_FACT_KEYS) }
    errors.add(:facts, "must not include contact details (#{bad_key})") if bad_key
    errors.add(:facts, "must not include an email address") if flat.any? { |v| v.match?(EMBEDDED_EMAIL) }
  end
end
