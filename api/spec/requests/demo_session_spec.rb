require "rails_helper"

RSpec.describe "Demo sign-in", type: :request do
  let(:center) { create(:center, name: "Little Oaks Early Learning") }
  let!(:renee) { create(:user, name: "Renee Albright", email_address: Demo::DIRECTOR_EMAIL, centers: [ center ]) }

  context "in a demo deployment" do
    before { allow(Demo).to receive(:deployed?).and_return(true) }

    it "says who the visitor will be signed in as" do
      get "/api/v1/demo_session"
      expect(response).to have_http_status(:ok)
      expect(json).to include("available" => true, "director_name" => "Renee Albright", "center_name" => "Little Oaks Early Learning")
    end

    it "signs the visitor in as the demo director with a cookie session" do
      post "/api/v1/demo_session", headers: same_origin, as: :json
      expect(response).to have_http_status(:created)
      expect(json["user"]["email_address"]).to eq(Demo::DIRECTOR_EMAIL)

      get "/api/v1/centers/#{center.id}/proposed_actions"
      expect(response).to have_http_status(:ok)
    end

    it "refuses a cross-site request so another page can't sign a visitor in" do
      post "/api/v1/demo_session", headers: { "Sec-Fetch-Site" => "cross-site" }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.cookies["session_id"]).to be_nil
    end

    it "limits demo sign-ins per address" do
      Rails.cache.clear
      20.times { post "/api/v1/demo_session", headers: same_origin, as: :json }
      post "/api/v1/demo_session", headers: same_origin, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it "is a 404 when the demo director hasn't been seeded" do
      renee.destroy!
      post "/api/v1/demo_session", headers: same_origin, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  it "does not exist outside a demo" do
    get "/api/v1/demo_session"
    expect(response).to have_http_status(:not_found)
    post "/api/v1/demo_session", headers: same_origin, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.cookies["session_id"]).to be_nil
  end
end
