require "rails_helper"

RSpec.describe "Proposed action decisions", type: :request do
  let(:center) { create(:center) }
  let(:user) { director_of(center) }
  let!(:action) { create(:proposed_action, center: center) }
  let(:base) { "/api/v1/centers/#{center.id}/proposed_actions" }

  before { sign_in(user) }

  def decide(verb, target = action, **params)
    post "#{base}/#{target.id}/#{verb}", params: { lock_version: target.lock_version }.merge(params),
                                         headers: same_origin, as: :json
  end

  describe "approve" do
    it "requires a message for family-facing actions" do
      decide(:approve, final_body: "   ")
      expect(response).to have_http_status(:unprocessable_content)
      expect(action.reload).to be_proposed
    end

    it "approves with the director's edited message and records who decided" do
      decide(:approve, final_body: "  Hi Jordan, a quick note about March tuition.  ")
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "approved", "final_body" => "Hi Jordan, a quick note about March tuition.",
                              "decided_by_name" => user.name, "lock_version" => 1)
      expect(action.transitions.last.actor).to eq("user:#{user.id}")
    end

    it "approves a staffing warning without a message" do
      ratio = create(:proposed_action, center: center, kind: "ratio_risk", dedupe_key: "ratio_risk:classroom:1:2026-10-20",
                                       occurs_on: Date.new(2026, 10, 20))
      decide(:approve, ratio)
      expect(response).to have_http_status(:ok)
      expect(json["family_facing"]).to be(false)
    end

    it "returns 409 with the current row for a stale lock_version and writes nothing (O6)" do
      post "#{base}/#{action.id}/approve", params: { lock_version: action.lock_version + 1, final_body: "Hi" },
                                           headers: same_origin, as: :json
      expect(response).to have_http_status(:conflict)
      expect(json["action"]).to include("id" => action.id, "status" => "proposed")
      expect(action.reload).to be_proposed
      expect(action.transitions).to be_empty
    end

    it "returns 409 when the action was already handled" do
      decide(:dismiss, reason: "duplicate")
      decide(:approve, action.reload, final_body: "Hi")
      expect(response).to have_http_status(:conflict)
      expect(json["action"]["status"]).to eq("dismissed")
    end

    it "requires lock_version" do
      post "#{base}/#{action.id}/approve", params: { final_body: "Hi" }, headers: same_origin, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "dismiss" do
    it "records the reason and moves the action out of the inbox" do
      decide(:dismiss, reason: "Family already paid by check")
      expect(json).to include("status" => "dismissed", "dismiss_reason" => "Family already paid by check")

      get base
      expect(json).to be_empty
      get base, params: { status: "dismissed" }
      expect(json.map { |a| a["id"] }).to eq([ action.id ])
    end
  end

  describe "snooze" do
    it "hides the action until the chosen time" do
      decide(:snooze, until: 2.days.from_now.iso8601)
      expect(response).to have_http_status(:ok)
      expect(json["lock_version"]).to eq(1)

      get base
      expect(json).to be_empty
      travel_to(3.days.from_now) do
        get base
        expect(json.map { |a| a["id"] }).to eq([ action.id ])
      end
    end

    it "rejects a time in the past, too far out, or unparseable" do
      [ 1.hour.ago.iso8601, 45.days.from_now.iso8601, "next tuesday" ].each do |value|
        decide(:snooze, until: value)
        expect(response).to have_http_status(:unprocessable_content), value
      end
      expect(action.reload.snoozed_until).to be_nil
    end

    it "returns 409 for a stale lock_version" do
      post "#{base}/#{action.id}/snooze", params: { lock_version: 7, until: 1.day.from_now.iso8601 },
                                          headers: same_origin, as: :json
      expect(response).to have_http_status(:conflict)
    end
  end

  it "lists approved actions newest decision first" do
    older = create(:proposed_action, center: center)
    decide(:approve, older, final_body: "First")
    decide(:approve, final_body: "Second")

    get base, params: { status: "approved" }
    expect(json.map { |a| a["final_body"] }).to eq(%w[Second First])
  end
end
