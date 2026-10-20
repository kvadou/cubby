require "rails_helper"

# Obligation O1 in docs/prior-art/2026-10-19-phase3-auth.md: a director of center A can neither read
# nor change center B, and the response does not reveal that B exists.
RSpec.describe "Center scoping", type: :request do
  let(:mine) { create(:center, name: "Mine") }
  let(:theirs) { create(:center, name: "Theirs") }
  let!(:their_action) { create(:proposed_action, center: theirs) }
  let!(:my_action) { create(:proposed_action, center: mine) }

  before do
    family = create(:family, center: theirs)
    create(:invoice, family: family, due_on: 10.days.ago.to_date)
    create(:enrollment, child: create(:child, family: family))
    create(:classroom, center: theirs)
    sign_in(director_of(mine))
  end

  it "lists only my centers" do
    get "/api/v1/centers"
    expect(json.map { |c| c["id"] }).to eq([ mine.id ])
  end

  %w[%s %s/classrooms %s/enrollments %s/invoices %s/proposed_actions].each do |template|
    it "404s on GET /centers/#{template % ':other'}" do
      get "/api/v1/centers/#{template % theirs.id}"
      expect(response).to have_http_status(:not_found)
      expect(json).to eq("error" => "not_found")
    end
  end

  %w[approve dismiss snooze].each do |verb|
    let(:params) { { lock_version: 0, final_body: "Hi", reason: "x", until: 1.day.from_now.iso8601 } }

    it "404s on #{verb} for another center's action" do
      post "/api/v1/centers/#{theirs.id}/proposed_actions/#{their_action.id}/#{verb}", params: params,
           headers: same_origin, as: :json
      expect(response).to have_http_status(:not_found)
      expect(their_action.reload.attributes).to eq(their_action.attributes)
      expect(their_action.reload).to be_proposed
    end

    it "404s on #{verb} for another center's action reached through my center's path" do
      post "/api/v1/centers/#{mine.id}/proposed_actions/#{their_action.id}/#{verb}", params: params,
           headers: same_origin, as: :json
      expect(response).to have_http_status(:not_found)
      expect(their_action.reload).to be_proposed
      expect(their_action.snoozed_until).to be_nil
    end
  end

  it "still serves my own center" do
    get "/api/v1/centers/#{mine.id}/proposed_actions"
    expect(json.map { |a| a["id"] }).to eq([ my_action.id ])
  end
end
