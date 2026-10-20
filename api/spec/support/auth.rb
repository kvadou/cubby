module AuthHelpers
  PASSWORD = "correct horse battery".freeze
  def same_origin = { "Sec-Fetch-Site" => "same-origin" }

  def json = JSON.parse(response.body)

  def director_of(*centers) = create(:user, centers: centers)

  def sign_in(user, password: PASSWORD)
    post "/api/v1/session", params: { email_address: user.email_address, password: password }, headers: same_origin, as: :json
    expect(response).to have_http_status(:created)
  end

  def bearer_token_for(user)
    post "/api/v1/tokens", params: { email_address: user.email_address, password: PASSWORD }, as: :json
    expect(response).to have_http_status(:created)
    json.fetch("token")
  end

  def bearer(token) = { "Authorization" => "Bearer #{token}" }
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  # Login rate limits count in Rails.cache; start every request spec from zero.
  config.before(type: :request) { Rails.cache.clear }
end
