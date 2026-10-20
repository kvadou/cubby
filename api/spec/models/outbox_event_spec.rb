require "rails_helper"

# Obligations O1 and O3 in docs/prior-art/2026-10-19-phase5-events.md.
RSpec.describe OutboxEvent do
  let(:center) { create(:center) }
  let(:action) { create(:proposed_action, center: center) }

  it "is written in the same transaction as an approval, with no message text" do
    action.update_columns(draft_status: "ready", draft_body: "Hi Jordan, draft.", draft_cost_micros: 1200)
    action.reload.approve!(by: "user:7", final_body: "Hi Jordan, draft.")

    event = described_class.sole
    expect(event.event_type).to eq("action.approved")
    expect(event.payload).to include("action_id" => action.id, "kind" => "past_due_invoice", "message_source" => "draft_as_is",
                                     "draft_cost_micros" => 1200, "decided_by_type" => "user", "family_facing" => true)
    expect(event.payload.to_json).not_to include("Jordan")
  end

  it "classifies edited drafts and messages written without a draft" do
    action.update_columns(draft_status: "ready", draft_body: "Draft text")
    action.reload.approve!(by: "user:1", final_body: "Edited text")
    other = create(:proposed_action, center: center)
    other.approve!(by: "user:1", final_body: "My own words")

    expect(described_class.order(:id).map { |e| e.payload["message_source"] }).to eq(%w[draft_edited starter_or_own])
  end

  it "writes nothing when the transition is rejected" do
    stale = ProposedAction.find(action.id)
    action.dismiss!(by: "user:1")
    expect { stale.approve!(by: "user:2", final_body: "x") }.to raise_error(ProposedAction::InvalidTransition)
    expect(described_class.pluck(:event_type)).to eq([ "action.dismissed" ])
  end

  it "keeps only the dismiss category, never the director's note" do
    action.dismiss!(by: "user:1", reason: "Something else: paid cash to Maria at pickup")
    expect(described_class.sole.payload).to include("reason_category" => "Something else")
    expect(described_class.sole.payload.to_json).not_to include("Maria")
  end

  it "records snoozes and resolutions" do
    action.snooze!(until_time: 2.days.from_now)
    action.reload.resolve!(resolution: "condition_cleared")
    expect(described_class.order(:id).pluck(:event_type)).to eq(%w[action.snoozed action.resolved])
  end

  it "rejects payloads with personal fields, at any depth" do
    expect { described_class.record!("action.approved", center_id: center.id, payload: { guardian_first_name: "Jo" }) }
      .to raise_error(ActiveRecord::RecordInvalid, /guardian_first_name/)
    expect { described_class.record!("action.approved", center_id: center.id, payload: { meta: [ { email: "a@b.c" } ] }) }
      .to raise_error(ActiveRecord::RecordInvalid, /email/)
  end

  it "records one proposed event per action a scan creates, and none on a rescan" do
    create(:invoice, family: create(:family, center: center), due_on: Date.new(2026, 10, 9))
    CenterScan.new(center, as_of: Date.new(2026, 10, 19)).call
    CenterScan.new(center, as_of: Date.new(2026, 10, 19)).call

    expect(described_class.where(event_type: "action.proposed").count).to eq(1)
    expect(described_class.sole.payload).to include("kind" => "past_due_invoice", "action_id" => center.proposed_actions.sole.id)
  end
end
