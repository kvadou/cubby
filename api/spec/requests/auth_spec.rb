require "rails_helper"

# Obligations O2, O4, O5 in docs/prior-art/2026-10-19-phase3-auth.md.
RSpec.describe "Authentication", type: :request do
  let(:center) { create(:center) }
  let(:user) { director_of(center) }

  it "rejects requests with no credentials" do
    get "/api/v1/me"
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/centers/#{center.id}/proposed_actions"
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a wrong password without saying which part was wrong" do
    post "/api/v1/session", params: { email_address: user.email_address, password: "nope nope nope" },
                            headers: same_origin, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(json["error"]).to eq("invalid_login")
    expect(response.cookies["session_id"]).to be_nil
  end

  it "treats a missing password as a failed login, not an error" do
    post "/api/v1/session", params: { email_address: user.email_address }, headers: same_origin, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  describe "cookie sessions" do
    it "signs in, ignores email case and spacing, and returns the director's centers" do
      post "/api/v1/session", params: { email_address: "  #{user.email_address.upcase} ", password: AuthHelpers::PASSWORD },
                              headers: same_origin, as: :json
      expect(response).to have_http_status(:created)
      expect(response.headers["Set-Cookie"]).to include("httponly").and include("samesite=lax")

      get "/api/v1/me"
      expect(json["user"]["email_address"]).to eq(user.email_address)
      expect(json["centers"].map { |c| c["id"] }).to eq([ center.id ])
    end

    it "revokes the session on sign out, even if the old cookie is replayed" do
      sign_in(user)
      saved = cookies[:session_id]

      delete "/api/v1/session", headers: same_origin
      expect(response).to have_http_status(:no_content)
      expect(Session.count).to eq(0)

      cookies[:session_id] = saved
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
    end

    it "expires after 30 days" do
      sign_in(user)
      travel_to(31.days.from_now) do
        get "/api/v1/me"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "bearer tokens" do
    it "authenticates with the token and stores only its digest (O4)" do
      token = bearer_token_for(user)
      expect(token.length).to be >= 40
      expect(Session.where(token_digest: token)).to be_empty
      expect(Session.sole.token_digest).to eq(Digest::SHA256.hexdigest(token))

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:ok)
    end

    it "revokes the token" do
      token = bearer_token_for(user)
      delete "/api/v1/tokens/current", headers: bearer(token)
      expect(response).to have_http_status(:no_content)

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not fall back to the cookie when a bad bearer token is sent" do
      sign_in(user)
      get "/api/v1/me", headers: bearer("forged")
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not accept a cookie session id as a token" do
      sign_in(user)
      get "/api/v1/me", headers: bearer(Session.sole.id.to_s)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "throttling (O5)" do
    it "blocks the 6th attempt for one email within 3 minutes, even with the right password" do
      5.times do
        post "/api/v1/tokens", params: { email_address: user.email_address, password: "wrong wrong wrong" }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      post "/api/v1/tokens", params: { email_address: user.email_address, password: AuthHelpers::PASSWORD }, as: :json
      expect(response).to have_http_status(:too_many_requests)

      # The cookie endpoint shares the same budget.
      post "/api/v1/session", params: { email_address: user.email_address, password: AuthHelpers::PASSWORD },
                              headers: same_origin, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
