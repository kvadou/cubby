require "rails_helper"

# End to end against Moto: approve -> outbox -> SNS -> SQS -> domain_events -> S3. Runs when
# EVENTS_AWS_ENDPOINT points at a Moto server (compose locally, a service container in CI).
RSpec.describe "Event pipeline", :moto do
  before do
    skip "set EVENTS_AWS_ENDPOINT to a Moto server to run" unless Events.endpoint
    Events.reset!
    Events::Setup.call
    Events::Consumer.poll_once(wait: 0) until Events.sqs.receive_message(queue_url: Events.queue_url, wait_time_seconds: 0).messages.empty?
  end

  after { Events.reset! }

  it "delivers an approval to analytics and exports it to S3" do
    action = create(:proposed_action)
    action.approve!(by: "user:1", final_body: "Hello")
    event_id = OutboxEvent.sole.event_id

    expect(Events::Publisher.call).to eq(1)
    received = 0
    5.times { received += Events::Consumer.poll_once(wait: 1) and break if received.zero? }
    expect(DomainEvent.find_by(event_id: event_id)).to have_attributes(event_type: "action.approved", center_id: action.center_id)

    export = Events::Exporter.call(OutboxEvent.sole.occurred_at.utc.to_date)
    body = Events.s3.get_object(bucket: Events::BUCKET, key: export[:key]).body.read
    expect(body).to include(event_id)
  end
end
