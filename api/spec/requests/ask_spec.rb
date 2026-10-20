require "rails_helper"

RSpec.describe "Ask Cubby", type: :request do
  let(:center) { create(:center) }
  let(:client) { stub_bedrock_client }

  before do
    Ai::Bedrock.client = client
    sign_in(director_of(center))
  end

  def ask(question, target = center)
    post "/api/v1/centers/#{target.id}/ask", params: { question: question }, headers: same_origin, as: :json
  end

  it "answers" do
    client.stub_responses(:converse, text_response("Three rooms have open seats."))
    ask("Which rooms have open seats?")
    expect(response).to have_http_status(:ok)
    expect(json).to include("text" => "Three rooms have open seats.", "steps" => [])
  end

  it "validates the question" do
    ask("  ")
    expect(response).to have_http_status(:unprocessable_content)
    ask("x" * 501)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 503 when Bedrock is unavailable" do
    client.stub_responses(:converse, "AccessDeniedException")
    ask("Anything?")
    expect(response).to have_http_status(:service_unavailable)
    expect(json["error"]).to eq("ai_unavailable")
  end

  it "limits each signed-in visitor separately, so one can't use up a shared demo account" do
    Rails.cache.clear
    client.stub_responses(:converse, text_response("Sure."))
    director = director_of(center)
    sign_in(director)
    20.times { ask("Anything?") }
    ask("Anything?")
    expect(response).to have_http_status(:too_many_requests)

    # Another visitor on the same account (a new session from another address) can still ask.
    reset!
    sign_in(director)
    post "/api/v1/centers/#{center.id}/ask", params: { question: "Anything?" },
                                             headers: same_origin.merge("REMOTE_ADDR" => "203.0.113.9"), as: :json
    expect(response).to have_http_status(:ok)
  end

  it "404s for another center" do
    ask("Anything?", create(:center))
    expect(response).to have_http_status(:not_found)
  end
end
