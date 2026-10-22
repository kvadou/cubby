require "rails_helper"

RSpec.describe "db/seeds/history.rb" do
  let!(:center) { create(:center, name: "Little Oaks Early Learning") }
  let(:seed) { -> { load Rails.root.join("db/seeds/history.rb") } }

  it "writes labelled past activity that the analytics report reads, and replaces it on re-run" do
    live = DomainEvent.create!(event_id: SecureRandom.uuid, event_type: "action.approved", center_id: center.id,
                               payload: { kind: "ratio_risk" }, occurred_at: 1.hour.ago, received_at: 1.hour.ago)
    seed.call
    count = DomainEvent.count
    seed.call

    expect(DomainEvent.count).to eq(count)
    expect(DomainEvent.exists?(live.id)).to be(true)
    history = DomainEvent.where.not(id: live.id)
    expect(history.map { |e| e.payload["demo_history"] }.uniq).to eq([ true ])
    expect(history.maximum(:occurred_at)).to be < Time.current

    report = Analytics::Report.new(center, days: 30).to_h
    expect(report[:totals][:approved]).to be > 20
    expect(report[:totals][:approval_rate]).to be_between(0.6, 0.95)
    expect(report[:median_hours_to_decision]).to be_positive
    expect(report[:messages][:draft_as_is]).to be_positive
    expect(report[:ai][:cost_per_approved_message_micros]).to be_positive
    expect(report[:daily].count { |d| d[:approved].positive? }).to be >= 15
    expect(report[:pipeline][:demo_history_through]).to be_present
  end
end
