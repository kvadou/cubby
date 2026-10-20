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

      rows, done = [], []
      messages.each do |m|
        row = parse(m.body)
        next Rails.logger.warn("analytics: unreadable message #{m.message_id}") unless row

        rows << row
        done << m
      end
      DomainEvent.insert_all(rows, unique_by: :event_id) if rows.any?
      done.each_slice(10) do |slice|
        Events.sqs.delete_message_batch(queue_url: Events.queue_url,
                                        entries: slice.map { |m| { id: m.message_id, receipt_handle: m.receipt_handle } })
      end
      rows.size
    end

    def parse(body)
      e = JSON.parse(body)
      return unless e.is_a?(Hash) && e["event_id"].present? && OutboxEvent::TYPES.include?(e["event_type"])

      { event_id: e["event_id"], event_type: e["event_type"], center_id: Integer(e["center_id"]),
        payload: e["data"].to_h, occurred_at: Time.iso8601(e["occurred_at"]), received_at: Time.current }
    rescue JSON::ParserError, ArgumentError, TypeError
      nil
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
