require "rails_helper"

RSpec.describe Drafting::Enqueue do
  let(:center) { create(:center) }

  around do |example|
    ENV["CUBBY_AI_DRAFTS"] = "on"
    example.run
  ensure
    ENV.delete("CUBBY_AI_DRAFTS")
  end

  it "queues one draft per open family-facing action without one, and marks them pending" do
    family_facing = create(:proposed_action, center: center)
    create(:proposed_action, center: center, kind: "ratio_risk", dedupe_key: "ratio_risk:classroom:1:2026-10-20")
    create(:proposed_action, center: center, draft_status: "ready")

    expect(described_class.for_center(center)).to eq(1)
    expect(DraftActionJob.jobs.map { |j| j["args"] }).to eq([ [ family_facing.id ] ])
    expect(family_facing.reload.draft_status).to eq("pending")
    expect(family_facing.lock_version).to eq(0) # a director mid-review must not get a false conflict
    expect(described_class.for_center(center)).to eq(0)
  end

  it "is off in tests unless enabled" do
    ENV.delete("CUBBY_AI_DRAFTS")
    create(:proposed_action, center: center)
    expect(described_class.for_center(center)).to eq(0)
  end
end
