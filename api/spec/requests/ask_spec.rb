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

  it "404s for another center" do
    ask("Anything?", create(:center))
    expect(response).to have_http_status(:not_found)
  end
end
