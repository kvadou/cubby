require "rails_helper"

RSpec.describe Ai::Bedrock do
  let(:client) { stub_bedrock_client }

  before { described_class.client = client }

  it "forces the named tool and returns its input with usage and cost" do
    client.stub_responses(:converse, tool_use_response("submit_draft", { "subject" => "Hi", "body" => "Hello" },
                                                       input_tokens: 1000, output_tokens: 200))
    result = described_class.structured(model: "us.anthropic.claude-haiku-4-5-20251001-v1:0", system: "s", prompt: "p",
                                        tool: Drafting::Prompt::TOOL)

    request = client.api_requests.last[:params]
    expect(request[:tool_config][:tool_choice]).to eq(tool: { name: "submit_draft" })
    expect(result.input).to eq("subject" => "Hi", "body" => "Hello")
    expect(result.cost_micros).to eq(2000) # 1000 * $1/M + 200 * $5/M = $0.002
  end

  it "raises when the model answers without calling the tool" do
    client.stub_responses(:converse, text_response("no"))
    expect {
      described_class.structured(model: "m", system: "s", prompt: "p", tool: Drafting::Prompt::TOOL)
    }.to raise_error(Ai::Bedrock::Error, /did not call submit_draft/)
  end

  it "wraps service errors" do
    client.stub_responses(:converse, "ThrottlingException")
    expect {
      described_class.structured(model: "m", system: "s", prompt: "p", tool: Drafting::Prompt::TOOL)
    }.to raise_error(Ai::Bedrock::Error)
  end

  it "embeds with Titan V2 at 1024 normalized dimensions" do
    client.stub_responses(:invoke_model, { body: StringIO.new({ embedding: axis_vector(3) }.to_json), content_type: "application/json" })
    expect(described_class.embed("late fee").size).to eq(1024)
    expect(JSON.parse(client.api_requests.last[:params][:body])).to include("dimensions" => 1024, "normalize" => true)
  end
end
