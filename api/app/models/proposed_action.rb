# One unit of proposed work for a director. See docs/prior-art/2026-10-19-phase2-action-queue.md.
#
# Lifecycle: proposed -> approved | dismissed | resolved. Every change goes through #transition!,
# which is a conditional UPDATE guarded by status and lock_version plus one history row, in one
# transaction. That method is also the seam where phase 5 adds the event outbox.
class ProposedAction < ApplicationRecord
  KINDS = %w[stale_waitlist past_due_invoice ratio_risk].freeze
  STATUSES = %w[proposed approved dismissed resolved].freeze
  RESOLUTIONS = %w[condition_cleared superseded expired].freeze
  # Kinds whose approval sends a message to a family, so approving one needs a message body.
  FAMILY_FACING = %w[stale_waitlist past_due_invoice].freeze
  # How long a closed condition stays quiet before a detector may raise it again (D5, D11 proposals).
  COOLDOWNS = { "stale_waitlist" => 14.days, "past_due_invoice" => 7.days }.freeze
  # Facts go to a language model in phase 4, so contact details never belong in them (D8).
  FORBIDDEN_FACT_KEYS = /email|phone|address/i
  # The web app's dismiss reasons. Events carry only the category, never the director's note.
  DISMISS_CATEGORIES = [ "Already handled", "Not accurate", "Family asked us to wait", "Something else" ].freeze
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

  # Background writes (scan refreshes, drafts) must not bump lock_version, or a director mid-review would
  # get a false conflict. Rails' update_all increments the locking column unless the update sets it.
  def self.update_quietly(attrs)
    update_all(attrs.merge(lock_version: Arel.sql("lock_version")))
  end

  # Detectors skip a key while a recently closed row for it is still cooling down.
  def self.suppressed?(dedupe_key, now = Time.current)
    where(dedupe_key: dedupe_key).where.not(status: "proposed").where("suppressed_until > ?", now).exists?
  end

  def family_facing? = FAMILY_FACING.include?(kind)

  # Approving a family-facing action delivers the message to the family's in-app inbox in the same
  # transaction, so an approval never exists without its message.
  def approve!(by:, final_body: nil, now: Time.current)
    body = final_body || draft_body
    self.class.transaction do
      transition!(to: "approved", actor: by, now: now,
                  attrs: { final_body: body, suppressed_until: cooldown_end(now) },
                  event: { family_facing: family_facing?, message_source: message_source(body), draft_status: draft_status,
                           draft_cost_micros: draft_cost_micros })
      deliver_to_family!(body, now) if family_facing?
    end
  end

  # Past-due tuition is about a family; a waitlist follow-up is about a child's enrollment.
  def family
    case subject
    when Family then subject
    when Enrollment then subject.child.family
    end
  end

  def dismiss!(by:, reason: nil, now: Time.current)
    category = DISMISS_CATEGORIES.find { |c| reason.to_s.start_with?(c) } || (reason.present? ? "Other" : "None")
    transition!(to: "dismissed", actor: by, note: reason, now: now,
                attrs: { dismiss_reason: reason, suppressed_until: cooldown_end(now) },
                event: { reason_category: category })
  end

  def resolve!(resolution:, by: "system", now: Time.current)
    raise ArgumentError, "unknown resolution #{resolution}" unless RESOLUTIONS.include?(resolution)
    transition!(to: "resolved", actor: by, resolution: resolution, now: now, attrs: { resolution: resolution },
                event: { resolution: resolution })
  end

  # Snoozing hides the row from the inbox without closing it, so it is not a status change.
  def snooze!(until_time:)
    raise InvalidTransition, "only proposed actions can be snoozed" unless proposed?

    self.class.transaction do
      update!(snoozed_until: until_time)
      OutboxEvent.record!("action.snoozed", center_id: center_id,
                          payload: event_payload(snoozed_until: until_time.iso8601))
    end
  end

  def transition!(to:, actor:, resolution: nil, note: nil, now: Time.current, attrs: {}, event: {})
    raise InvalidTransition, "unknown status #{to}" unless STATUSES.include?(to)

    self.class.transaction do
      changes = attrs.merge(status: to, decided_at: now, decided_by: actor, snoozed_until: nil,
                            lock_version: lock_version + 1, updated_at: now)
      updated = self.class.where(id: id, status: "proposed", lock_version: lock_version).update_all(changes)
      raise InvalidTransition, "action #{id} is no longer proposed or was changed by someone else" if updated.zero?

      ProposedActionTransition.create!(proposed_action_id: id, from_status: status, to_status: to,
                                       resolution: resolution, actor: actor, note: note, created_at: now)
      OutboxEvent.record!("action.#{to}", center_id: center_id, occurred_at: now,
                          payload: event_payload(decided_at: now.iso8601(6), decided_by_type: actor.to_s.split(":").first,
                                                 **event))
      reload
    end
  end

  # The fields every action event carries: enough to count and time decisions, nothing personal.
  def event_payload(**extra)
    { action_id: id, kind: kind, proposed_at: detected_at.iso8601(6) }.merge(extra)
  end

  private

  DEFAULT_SUBJECTS = { "stale_waitlist" => "A spot at %s", "past_due_invoice" => "Your tuition balance at %s" }.freeze

  def deliver_to_family!(body, now)
    raise InvalidTransition, "action #{id} has no message to send" if body.blank?

    FamilyMessage.create!(family: family, center_id: center_id, proposed_action_id: id, body: body, sent_at: now,
                          subject: draft_subject.presence || format(DEFAULT_SUBJECTS.fetch(kind), center.name))
  end

  # How the approved message came about, for the "drafts used as written" metric.
  def message_source(body)
    return "none" unless family_facing?
    return "starter_or_own" unless draft_status == "ready" && draft_body.present?

    body.to_s.strip == draft_body.strip ? "draft_as_is" : "draft_edited"
  end

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
