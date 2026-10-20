module Events
  # Writes one UTC day's events to S3 as JSON lines, partitioned by date for later querying with Athena.
  # Partitions are UTC days so they line up across centers in different time zones. Re-running a day
  # overwrites the same key.
  module Exporter
    module_function

    def call(date)
      events = DomainEvent.where(occurred_at: date.in_time_zone("UTC").all_day).order(:occurred_at)
      key = "events/date=#{date.iso8601}/events.jsonl"
      body = events.map { |e| e.slice(:event_id, :event_type, :center_id, :payload, :occurred_at).to_json }.join("\n")
      Events.s3.put_object(bucket: Events::BUCKET, key: key, body: body, content_type: "application/x-ndjson")
      { key: key, count: events.size }
    end
  end
end
