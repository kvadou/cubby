require "rails_helper"

# Obligation O4 in docs/prior-art/2026-10-19-phase5-events.md.
RSpec.describe Events::Consumer do
  let(:sqs) { Aws::SQS::Client.new(stub_responses: true, region: "us-east-1", credentials: Aws::Credentials.new("t", "t")) }
  let(:event_id) { SecureRandom.uuid }
  let(:good) do
    { event_id: event_id, event_type: "action.approved", center_id: 3, occurred_at: "2026-10-19T15:00:00.000000Z",
      data: { action_id: 9, kind: "past_due_invoice" } }.to_json
  end

  before do
    Events.reset!(sqs: sqs)
    sqs.stub_responses(:get_queue_url, { queue_url: "http://localhost/q" })
  end

  after { Events.reset! }

  def deliver(*bodies)
    sqs.stub_responses(:receive_message, { messages: bodies.each_with_index.map { |b, i| { message_id: "m#{i}", receipt_handle: "r#{i}", body: b } } })
  end

  def deleted = sqs.api_requests.select { |r| r[:operation_name] == :delete_message_batch }.flat_map { |r| r[:params][:entries].map { |e| e[:id] } }

  it "records each event once, even when SQS delivers it twice" do
    deliver(good, good)
    expect(described_class.poll_once(wait: 0)).to eq(2)
    expect(DomainEvent.sole).to have_attributes(event_id: event_id, event_type: "action.approved", center_id: 3)
    expect(DomainEvent.sole.payload).to eq("action_id" => 9, "kind" => "past_due_invoice")
    expect(deleted).to eq(%w[m0 m1])

    deliver(good)
    described_class.poll_once(wait: 0)
    expect(DomainEvent.count).to eq(1)
  end

  it "keeps running when the queue doesn't exist yet, and picks it up once it does" do
    sqs.stub_responses(:get_queue_url, [ "NonExistentQueue", { queue_url: "http://localhost/q" } ])
    deliver(good)
    polls = 0
    described_class.run(stop: -> { (polls += 1) > 2 }, pause: 0)
    expect(DomainEvent.sole.event_id).to eq(event_id)
  end

  it "leaves unreadable messages for the dead-letter queue" do
    deliver("not json", { event_type: "action.approved" }.to_json, good)
    expect(described_class.poll_once(wait: 0)).to eq(1)
    expect(deleted).to eq(%w[m2])
  end

  it "never lets a malformed message take good ones down with it" do
    base = JSON.parse(good)
    bad = [
      base.merge("event_id" => "not-a-uuid"),
      base.merge("event_id" => SecureRandom.uuid, "data" => "x"),
      base.merge("event_id" => SecureRandom.uuid, "center_id" => 2**70),
      base.merge("event_id" => SecureRandom.uuid, "occurred_at" => "yesterday")
    ].map(&:to_json)
    deliver(*bad, good)

    expect(described_class.poll_once(wait: 0)).to eq(1)
    expect(DomainEvent.sole.event_id).to eq(event_id)
    expect(deleted).to eq(%w[m4])
  end
end
