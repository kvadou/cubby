require "rails_helper"

RSpec.describe "API v1", type: :request do
  let(:center) { create(:center) }
  let(:room) { create(:classroom, center: center, capacity: 3, ratio: 2) }

  before { sign_in(director_of(center)) }

  it "summarizes a center" do
    family = create(:family, center: center)
    create(:enrollment, :enrolled, classroom: room, child: create(:child, family: family))
    create(:enrollment, child: create(:child, family: family))
    create(:invoice, family: family, due_on: 10.days.ago.to_date)

    get "/api/v1/centers/#{center.id}"

    expect(response).to have_http_status(:ok)
    expect(json["counts"]).to include("enrolled" => 1, "waitlisted" => 1, "past_due_invoices" => 1)
  end

  it "reports staffing against ratio for a date" do
    date = Date.new(2026, 10, 20)
    create_list(:enrollment, 3, :enrolled, classroom: room)
    create(:staff_shift, classroom: room, starts_at: date.in_time_zone.change(hour: 8), ends_at: date.in_time_zone.change(hour: 16))

    get "/api/v1/centers/#{center.id}/classrooms", params: { on: date.to_s }

    expect(json.first).to include("expected_children" => 3, "scheduled_staff" => 1, "staff_required" => 2, "open_seats" => 0)
  end

  it "rejects an unparseable date" do
    get "/api/v1/centers/#{center.id}/classrooms", params: { on: "not-a-date" }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "filters invoices to past due" do
    family = create(:family, center: center)
    late = create(:invoice, family: family, due_on: 9.days.ago.to_date)
    create(:invoice, family: family, due_on: 5.days.from_now.to_date)

    get "/api/v1/centers/#{center.id}/invoices", params: { status: "past_due" }

    expect(json.map { |i| i["id"] }).to eq([ late.id ])
  end

  it "does not leak another center's data" do
    other = create(:center, name: "Other")
    create(:enrollment, child: create(:child, family: create(:family, center: other)))

    get "/api/v1/centers/#{center.id}/enrollments"

    expect(json).to be_empty
  end

  it "lists the inbox, hiding snoozed and closed actions and other centers' actions" do
    open_action = create(:proposed_action, center: center)
    create(:proposed_action, center: center).snooze!(until_time: 1.day.from_now)
    create(:proposed_action, center: center).dismiss!(by: "renee")
    create(:proposed_action, center: create(:center, name: "Other"))

    get "/api/v1/centers/#{center.id}/proposed_actions"

    expect(json.map { |a| a["id"] }).to eq([ open_action.id ])
    expect(json.first).to include("kind" => "past_due_invoice", "facts" => include("guardian_first_name" => "Jordan"))
  end

  it "returns 404 for an unknown center" do
    get "/api/v1/centers/0"
    expect(response).to have_http_status(:not_found)
  end
end
