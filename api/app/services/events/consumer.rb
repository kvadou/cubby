module Events
  # Long-polls the analytics queue and records each event once. A message is deleted only after its row
  # is committed; a message that can't be parsed is left alone so SQS moves it to the dead-letter queue
  # after five receives (D4).
  module Consumer
    module_function

    def poll_once(wait: 10)
      messages = Events.sqs.receive_message(queue_url: Events.queue_url, max_number_of_messages: 10,
                                            wait_time_seconds: wait).messages
      return 0 if messages.empty?

      parsed = messages.filter_map do |m|
        row = parse(m.body)
        Rails.logger.warn("analytics: unreadable message #{m.message_id}") unless row
        [ m, row ] if row
      end
      done = store(parsed)
      done.each_slice(10) do |slice|
        Events.sqs.delete_message_batch(queue_url: Events.queue_url,
                                        entries: slice.map { |m| { id: m.message_id, receipt_handle: m.receipt_handle } })
      end
      done.size
    end

    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    MAX_ID = (2**63) - 1

    # Returns a row, or nil for anything malformed. Never raises: one bad message must not take the
    # rest of its batch down with it.
    def parse(body)
      e = JSON.parse(body)
      return unless e.is_a?(Hash) && e["event_id"].to_s.match?(UUID) && OutboxEvent::TYPES.include?(e["event_type"])
      return unless e["data"].is_a?(Hash)

      center_id = Integer(e["center_id"])
      return unless center_id.between?(1, MAX_ID)

      { event_id: e["event_id"], event_type: e["event_type"], center_id: center_id,
        payload: e["data"], occurred_at: Time.iso8601(e["occurred_at"].to_s), received_at: Time.current }
    rescue StandardError
      nil
    end

    # Inserts the batch; if the database rejects it, retries row by row so only the bad message stays
    # behind for the dead-letter queue. Returns the messages that are safe to delete.
    def store(parsed)
      return [] if parsed.empty?

      DomainEvent.insert_all(parsed.map(&:last), unique_by: :event_id)
      parsed.map(&:first)
    rescue ActiveRecord::ActiveRecordError, ActiveModel::RangeError
      parsed.filter_map do |message, row|
        DomainEvent.insert_all([ row ], unique_by: :event_id)
        message
      rescue ActiveRecord::ActiveRecordError, ActiveModel::RangeError => e
        Rails.logger.warn("analytics: could not store #{message.message_id}: #{e.class}")
        nil
      end
    end

    # Keeps polling through outages, including a queue that doesn't exist yet (the consumer can start
    # before setup creates it), instead of exiting.
    def run(stop: -> { false }, pause: 5)
      Rails.logger.info("analytics consumer starting (queue #{Events::QUEUE_NAME})")
      until stop.call
        begin
          poll_once
        rescue *AWS_TRANSIENT_ERRORS => e
          Rails.logger.warn("analytics consumer: #{e.class}: #{e.message}; retrying in #{pause} s")
          Events.forget_queue_url!
          sleep pause
        end
      end
    end
  end
end
