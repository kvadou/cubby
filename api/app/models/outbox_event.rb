# One fact about something that happened, waiting to be published. See Events::Publisher.
class OutboxEvent < ApplicationRecord
  TYPES = %w[action.proposed action.approved action.dismissed action.resolved action.snoozed draft.completed].freeze
  # Events leave the app, so they carry ids, kinds, timings, and costs, never names, message text,
  # or free-text reasons (D3).
  FORBIDDEN_PAYLOAD_KEYS = /name|body|email|phone|address|note|subject|text/i

  belongs_to :center

  validates :event_type, inclusion: { in: TYPES }
  validate :payload_has_no_personal_data

  scope :unpublished, -> { where(published_at: nil) }

  # Call inside the transaction that makes the change. Publishing is kicked off once it commits;
  # the every-minute cron job catches anything a kick missed.
  def self.record!(event_type, center_id:, payload:, occurred_at: Time.current)
    create!(event_type: event_type, center_id: center_id, payload: payload, occurred_at: occurred_at)
    ActiveRecord.after_all_transactions_commit { PublishOutboxJob.perform_async if Events.enabled? }
  end

  # Bulk form for scans; one kick for the whole batch.
  def self.record_all!(event_type, center_id:, payloads:, occurred_at: Time.current)
    return if payloads.empty?

    payloads.each { |p| new(event_type: event_type, center_id: center_id, payload: p).validate! }
    insert_all(payloads.map { |p| { event_type: event_type, center_id: center_id, payload: p, occurred_at: occurred_at } })
    ActiveRecord.after_all_transactions_commit { PublishOutboxJob.perform_async if Events.enabled? }
  end

  def envelope
    { event_id: event_id, event_type: event_type, center_id: center_id, occurred_at: occurred_at.iso8601(6), data: payload }
  end

  private

  def payload_has_no_personal_data
    bad = payload.to_h.keys.grep(FORBIDDEN_PAYLOAD_KEYS)
    errors.add(:payload, "must not include #{bad.join(', ')}") if bad.any?
  end
end
