require "rails_helper"

RSpec.describe Agent::AskCubby do
  let(:center) { create(:center) }
  let(:client) { stub_bedrock_client }
  let!(:family) do
    create(:family, center: center, name: "Effertz family", primary_guardian_name: "Roman Effertz", email: "roman@example.com").tap do |f|
      create(:invoice, family: f, number: "LO-1162", amount_cents: 135_000, due_on: center.today - 20)
    end
  end

  it "runs read-only tools scoped to the center and returns the answer with its steps" do
    other = create(:center)
    create(:family, center: other, name: "Effertz family", primary_guardian_name: "Other Effertz")
    client.stub_responses(:converse, [
      tool_use_response("find_family", { "name" => "Effertz" }),
      text_response("The Effertz family owes $1,350.00 on LO-1162, 20 days past due.")
    ])

    answer = described_class.new(center: center, client: client, model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0").call("What does Effertz owe?")

    expect(answer.text).to include("$1,350.00")
    expect(answer.steps).to eq([ { tool: "find_family", input: { "name" => "Effertz" } } ])
    expect(answer.cost_micros).to eq(Ai::Bedrock.cost_micros(answer.model, 180, 70))

    tool_result = client.api_requests.last[:params][:messages].last[:content].first[:tool_result][:content].first[:text]
    data = JSON.parse(tool_result)
    expect(data["families"].size).to eq(1)
    expect(data["families"].first).to include("guardian_first_name" => "Roman")
    expect(data["families"].first["open_invoices"].first).to include("number" => "LO-1162", "amount" => "$1,350.00")
    expect(tool_result).not_to include("roman@example.com")
  end

  it "stops after a bounded number of tool turns" do
    client.stub_responses(:converse, Array.new(Agent::AskCubby::MAX_TURNS) { tool_use_response("open_actions", {}) })
    answer = described_class.new(center: center, client: client).call("Loop forever")
    expect(answer.steps.size).to eq(Agent::AskCubby::MAX_TURNS)
    expect(answer.text).to include("couldn't finish")
  end

  it "reports a bad date to the model instead of raising" do
    expect(Agent::Tools.new(center).run("classroom_staffing", { "date" => "tomorrow" })).to eq(error: "dates look like 2026-10-20")
  end
end
