require "rails_helper"

# Obligations O1 to O3 in docs/prior-art/2026-10-19-phase7-ios.md: a parent sees only their own family,
# never a director endpoint; a director never sees the family endpoints; approving a family-facing
# action delivers exactly one message to that family.
RSpec.describe "Family (parent) API", type: :request do
  let(:center) { create(:center, name: "Little Oaks") }
  let(:family) { create(:family, center: center, name: "Mine") }
  let(:other_family) { create(:family, center: center, name: "Theirs") }
  let(:room) { create(:classroom, center: center, name: "Maples") }
  let!(:child) { create(:child, family: family, first_name: "Meryl") }
  let!(:other_child) { create(:child, family: other_family, first_name: "Other") }
  let(:parent) { create(:user, families: [ family ]) }
  let(:token) { bearer_token_for(parent) }

  before do
    create(:enrollment, child: child, classroom: room, status: "enrolled", enrolled_on: 1.month.ago.to_date)
    create(:invoice, family: family, due_on: 10.days.ago.to_date, number: "MINE-1")
    create(:invoice, family: other_family, due_on: 10.days.ago.to_date, number: "THEIRS-1")
    Attendance.create!(child: child, classroom: room, on: center.today, checked_in_at: 2.hours.ago)
    Attendance.create!(child: other_child, classroom: room, on: center.today, checked_in_at: 2.hours.ago)
  end

  it "shows the parent's family, children, and today's check-in" do
    get "/api/v1/family", headers: bearer(token)
    expect(response).to have_http_status(:ok)
    expect(json["family"]["name"]).to eq("Mine")
    expect(json["children"].map { |c| c["first_name"] }).to eq([ "Meryl" ])
    expect(json["children"].first).to include("classroom" => "Maples", "status" => "enrolled")
    expect(json["children"].first["today"]["checked_in_at"]).to be_present
  end

  it "lists the family's invoices only" do
    get "/api/v1/family/invoices", headers: bearer(token)
    expect(json.map { |i| i["number"] }).to eq([ "MINE-1" ])
    expect(json.first["days_past_due"]).to eq(10)
  end

  it "404s on another family's child" do
    get "/api/v1/family/children/#{other_child.id}/attendance", headers: bearer(token)
    expect(response).to have_http_status(:not_found)
  end

  it "returns a child's recent attendance" do
    get "/api/v1/family/children/#{child.id}/attendance?days=7", headers: bearer(token)
    expect(json.size).to eq(1)
    expect(json.first).to include("classroom" => "Maples")
  end

  it "404s on another family's message and leaves it unread" do
    theirs = other_family.messages.create!(center: center, subject: "Hi", body: "Theirs", sent_at: Time.current)
    post "/api/v1/family/messages/#{theirs.id}/read", headers: bearer(token)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.read_at).to be_nil
  end

  it "marks a message read once and keeps the first read time" do
    message = family.messages.create!(center: center, subject: "Hi", body: "Hello", sent_at: 1.hour.ago)
    post "/api/v1/family/messages/#{message.id}/read", headers: bearer(token)
    first = message.reload.read_at
    travel 5.minutes do
      post "/api/v1/family/messages/#{message.id}/read", headers: bearer(token)
    end
    expect(message.reload.read_at).to eq(first)
    get "/api/v1/family", headers: bearer(token)
    expect(json["unread_messages"]).to eq(0)
  end

  it "includes the parent's families in me, and no centers" do
    get "/api/v1/me", headers: bearer(token)
    expect(json["centers"]).to eq([])
    expect(json["families"]).to eq([ { "id" => family.id, "name" => "Mine", "center_name" => "Little Oaks" } ])
  end

  describe "a parent on director endpoints" do
    let!(:action) { create(:proposed_action, center: center, subject: family) }

    %w[%s %s/invoices %s/enrollments %s/proposed_actions %s/analytics].each do |template|
      it "404s on GET /centers/#{template % ':id'}" do
        get "/api/v1/centers/#{template % center.id}", headers: bearer(token)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "can't approve their own family's action" do
      post "/api/v1/centers/#{center.id}/proposed_actions/#{action.id}/approve",
           params: { lock_version: 0, final_body: "Approved by me" }, headers: bearer(token), as: :json
      expect(response).to have_http_status(:not_found)
      expect(action.reload).to be_proposed
      expect(FamilyMessage.count).to eq(0)
    end
  end

  it "404s for a director, who has no family" do
    get "/api/v1/family", headers: bearer(bearer_token_for(director_of(center)))
    expect(response).to have_http_status(:not_found)
  end

  it "requires sign-in" do
    get "/api/v1/family"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "delivery on approval" do
    let(:director) { director_of(center) }

    it "delivers the approved text to the family it is about, once" do
      action = create(:proposed_action, center: center, subject: family)
      post "/api/v1/centers/#{center.id}/proposed_actions/#{action.id}/approve",
           params: { lock_version: 0, final_body: "Your balance is past due." },
           headers: bearer(bearer_token_for(director)), as: :json
      expect(response).to have_http_status(:ok)

      message = FamilyMessage.sole
      expect(message).to have_attributes(family_id: family.id, proposed_action_id: action.id,
                                         body: "Your balance is past due.", subject: "Your tuition balance at Little Oaks")

      get "/api/v1/family/messages", headers: bearer(token)
      expect(json.map { |m| m["body"] }).to eq([ "Your balance is past due." ])
      get "/api/v1/family/messages", headers: bearer(bearer_token_for(create(:user, families: [ other_family ])))
      expect(json).to eq([])
    end

    it "finds the family through a waitlisted child's enrollment" do
      enrollment = create(:enrollment, child: create(:child, family: family), status: "waitlisted",
                                       classroom: nil, waitlisted_at: 20.days.ago)
      action = create(:proposed_action, center: center, kind: "stale_waitlist", subject: enrollment,
                                        dedupe_key: "stale_waitlist:enrollment:#{enrollment.id}")
      action.approve!(by: "user:1", final_body: "A spot opened up.")
      expect(FamilyMessage.sole).to have_attributes(family_id: family.id, subject: "A spot at Little Oaks")
    end

    it "sends nothing for a staffing warning" do
      action = create(:proposed_action, center: center, kind: "ratio_risk", subject: room,
                                        dedupe_key: "ratio_risk:classroom:#{room.id}", occurs_on: center.today)
      action.approve!(by: "user:1")
      expect(FamilyMessage.count).to eq(0)
    end

    it "rolls the approval back if the message can't be written" do
      action = create(:proposed_action, center: center, subject: family)
      allow(FamilyMessage).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect { action.approve!(by: "user:1", final_body: "Hi") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(action.reload).to be_proposed
      expect(OutboxEvent.where(event_type: "action.approved")).to be_empty
    end
  end
end
