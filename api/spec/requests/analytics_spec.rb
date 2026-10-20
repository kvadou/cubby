require "rails_helper"

# Obligation O5 in docs/prior-art/2026-10-19-phase5-events.md.
RSpec.describe "Analytics", type: :request do
  let(:center) { create(:center, timezone: "America/Chicago") }
  let(:now) { Time.zone.parse("2026-10-19 15:00") }

  before { sign_in(director_of(center)) }

  def event(type, at:, center_id: center.id, **payload)
    DomainEvent.create!(event_id: SecureRandom.uuid, event_type: type, center_id: center_id, payload: payload,
                        occurred_at: at, received_at: at)
  end

  it "summarizes decisions, timing, draft use, and AI cost from received events only" do
    t = now - 2.days
    event("action.proposed", at: t, action_id: 1, kind: "past_due_invoice")
    event("action.proposed", at: t, action_id: 2, kind: "stale_waitlist")
    event("action.proposed", at: t, action_id: 3, kind: "ratio_risk")
    event("draft.completed", at: t, action_id: 1, kind: "past_due_invoice", status: "ready", cost_micros: 3000)
    event("draft.completed", at: t, action_id: 2, kind: "stale_waitlist", status: "ready", cost_micros: 1000)
    event("action.approved", at: t + 2.hours, action_id: 1, kind: "past_due_invoice", family_facing: true,
          message_source: "draft_as_is", proposed_at: t.iso8601, decided_at: (t + 2.hours).iso8601)
    event("action.approved", at: t + 4.hours, action_id: 2, kind: "stale_waitlist", family_facing: true,
          message_source: "draft_edited", proposed_at: t.iso8601, decided_at: (t + 4.hours).iso8601)
    event("action.dismissed", at: t + 6.hours, action_id: 3, kind: "ratio_risk", reason_category: "Not accurate",
          proposed_at: t.iso8601, decided_at: (t + 6.hours).iso8601)
    event("action.approved", at: t, center_id: create(:center).id, action_id: 99, kind: "ratio_risk") # another center
    OutboxEvent.record!("action.snoozed", center_id: center.id, payload: { action_id: 1, kind: "past_due_invoice" })

    travel_to(now) { get "/api/v1/centers/#{center.id}/analytics", params: { days: 7 } }

    expect(json["totals"]).to include("proposed" => 3, "approved" => 2, "dismissed" => 1, "approval_rate" => 0.667)
    expect(json["median_hours_to_decision"]).to eq(4.0)
    expect(json["messages"]).to include("approved" => 2, "draft_as_is" => 1, "draft_edited" => 1)
    expect(json["ai"]).to include("drafts" => 2, "cost_micros" => 4000, "cost_per_approved_message_micros" => 2000)
    expect(json["by_kind"].find { |k| k["kind"] == "ratio_risk" }).to include("dismissed" => 1, "approved" => 0)
    expect(json["daily"].size).to eq(7)
    expect(json["daily"].sum { |d| d["approved"] }).to eq(2)
    expect(json["pipeline"]["waiting_to_publish"]).to eq(1)
  end

  it "is empty, not an error, before any events arrive" do
    get "/api/v1/centers/#{center.id}/analytics"
    expect(json).to include("days" => 30, "median_hours_to_decision" => nil)
    expect(json["totals"]["approval_rate"]).to be_nil
  end

  it "404s for another center" do
    get "/api/v1/centers/#{create(:center).id}/analytics"
    expect(response).to have_http_status(:not_found)
  end
end
