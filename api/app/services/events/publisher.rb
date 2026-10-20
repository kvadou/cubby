module Events
  # Relays unpublished outbox rows to SNS in batches of ten. Rows are claimed with FOR UPDATE SKIP LOCKED,
  # so several relays never send the same row at once; a row is marked published only after SNS accepts
  # it, so a crash means a duplicate publish, never a lost event (D2). Consumers dedupe by event_id.
  module Publisher
    BATCH = 10 # SNS PublishBatch maximum
    MAX_ATTEMPTS = 10

    module_function

    def call(limit: 500)
      return 0 unless Events.enabled?

      published = 0
      while published < limit
        sent = publish_batch
        break if sent.nil?

        published += sent
      end
      published
    end

    # Returns the number published, or nil when nothing was left to claim.
    def publish_batch
      OutboxEvent.transaction do
        rows = OutboxEvent.unpublished.where("attempts < ?", MAX_ATTEMPTS).order(:id).limit(BATCH).lock("FOR UPDATE SKIP LOCKED").to_a
        return nil if rows.empty?

        result = Events.sns.publish_batch(topic_arn: Events.topic_arn, publish_batch_request_entries: rows.map { |r| entry(r) })
        ok_ids = result.successful.map { |s| s.id.to_i }
        OutboxEvent.where(id: ok_ids).update_all(published_at: Time.current, updated_at: Time.current) if ok_ids.any?
        result.failed.each do |f|
          OutboxEvent.where(id: f.id.to_i).update_all([ "attempts = attempts + 1, last_error = ?, updated_at = ?", "#{f.code}: #{f.message}".first(500), Time.current ])
        end
        ok_ids.size
      end
    rescue *AWS_TRANSIENT_ERRORS => e
      Rails.logger.warn("outbox publish failed: #{e.class}: #{e.message}")
      nil
    end

    def entry(row)
      { id: row.id.to_s, message: row.envelope.to_json,
        message_attributes: { "event_type" => { data_type: "String", string_value: row.event_type } } }
    end
  end
end
