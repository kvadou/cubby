require "rails_helper"

# Obligation O3 in docs/prior-art/2026-10-19-phase3-auth.md.
RSpec.describe "Cross-site request protection", type: :request do
  let(:center) { create(:center) }
  let(:user) { director_of(center) }
  let!(:action) { create(:proposed_action, center: center) }
  let(:path) { "/api/v1/centers/#{center.id}/proposed_actions/#{action.id}/dismiss" }
  let(:body) { { lock_version: action.lock_version, reason: "test" } }

  before { sign_in(user) }

  {
    "a cross-site request" => { "Sec-Fetch-Site" => "cross-site" },
    "a same-site request from a sibling subdomain" => { "Sec-Fetch-Site" => "same-site" },
    "an older browser posting from a foreign Origin" => { "Origin" => "https://evil.example" },
    "an Origin of null" => { "Origin" => "null" },
    "a request with neither header" => {}
  }.each do |label, headers|
    it "rejects #{label} that relies on the cookie" do
      post path, params: body, headers: headers, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(action.reload).to be_proposed
    end
  end

  it "allows same-origin requests" do
    post path, params: body, headers: same_origin, as: :json
    expect(response).to have_http_status(:ok)
    expect(action.reload).to be_dismissed
  end

  it "allows an older browser posting from the web app's origin" do
    post path, params: body, headers: { "Origin" => "http://localhost:5173" }, as: :json
    expect(response).to have_http_status(:ok)
  end

  it "does not apply to bearer requests, which a browser never sends on its own" do
    token = bearer_token_for(user)
    post path, params: body, headers: bearer(token).merge("Sec-Fetch-Site" => "cross-site"), as: :json
    expect(response).to have_http_status(:ok)
  end

  it "protects the sign-in endpoint against login CSRF" do
    post "/api/v1/session", params: { email_address: user.email_address, password: AuthHelpers::PASSWORD },
                            headers: { "Sec-Fetch-Site" => "cross-site" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
