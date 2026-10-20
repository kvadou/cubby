require "rails_helper"

# Obligation O2 in docs/prior-art/2026-10-19-phase5-events.md.
RSpec.describe Events::Publisher do
  let(:center) { create(:center) }
  let(:sns) { Aws::SNS::Client.new(stub_responses: true, region: "us-east-1", credentials: Aws::Credentials.new("t", "t")) }

  around do |example|
    ENV["EVENTS_AWS_ENDPOINT"] = "http://localhost:5055"
    Events.reset!(sns: sns)
    example.run
  ensure
    ENV.delete("EVENTS_AWS_ENDPOINT")
    Events.reset!
  end

  def record(n)
    n.times { |i| OutboxEvent.record!("action.snoozed", center_id: center.id, payload: { action_id: i, kind: "stale_waitlist" }) }
  end

  it "publishes in batches of ten and marks rows published" do
    record(12)
    sns.stub_responses(:publish_batch, ->(ctx) {
      { successful: ctx.params[:publish_batch_request_entries].map { |e| { id: e[:id], message_id: "m-#{e[:id]}" } }, failed: [] }
    })

    expect(described_class.call).to eq(12)
    batches = sns.api_requests.select { |r| r[:operation_name] == :publish_batch }
    expect(batches.map { |r| r[:params][:publish_batch_request_entries].size }).to eq([ 10, 2 ])
    body = JSON.parse(batches.first[:params][:publish_batch_request_entries].first[:message])
    expect(body).to include("event_type" => "action.snoozed", "center_id" => center.id, "event_id" => OutboxEvent.first.event_id)
    expect(OutboxEvent.unpublished.count).to eq(0)
  end

  it "leaves rejected entries unpublished and counts the caller's own faults" do
    record(2)
    sns.stub_responses(:publish_batch, ->(ctx) {
      first, second = ctx.params[:publish_batch_request_entries]
      { successful: [ { id: first[:id], message_id: "m" } ], failed: [ { id: second[:id], code: "InvalidParameter", sender_fault: true, message: "bad entry" } ] }
    })

    described_class.publish_batch
    failed = OutboxEvent.unpublished.sole
    expect(failed).to have_attributes(attempts: 1, last_error: "InvalidParameter: bad entry")
  end

  it "stops when a batch makes no progress, and doesn't count throttling toward the cap" do
    record(1)
    sns.stub_responses(:publish_batch, ->(ctx) {
      { successful: [], failed: [ { id: ctx.params[:publish_batch_request_entries].first[:id], code: "Throttled", sender_fault: false, message: "slow down" } ] }
    })

    expect(described_class.call).to eq(0)
    expect(sns.api_requests.count { |r| r[:operation_name] == :publish_batch }).to eq(1)
    expect(OutboxEvent.sole).to have_attributes(attempts: 0, last_error: "Throttled: slow down")
  end

  it "keeps everything for the next run when SNS is unreachable" do
    record(3)
    sns.stub_responses(:publish_batch, Seahorse::Client::NetworkingError.new(Errno::ECONNREFUSED.new))
    expect(described_class.call).to eq(0)
    expect(OutboxEvent.unpublished.count).to eq(3)
  end

  it "publishes nothing outside production without a local endpoint" do
    record(1)
    ENV.delete("EVENTS_AWS_ENDPOINT")
    expect(described_class.call).to eq(0)
    expect(sns.api_requests).to be_empty
  end
end
