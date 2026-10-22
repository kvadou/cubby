require "rails_helper"

module AnthropicConverseSpec
  # Stands in for Anthropic::Client: records each beta.messages.create call and returns queued messages
  # shaped like the SDK's (blocks answer #type, #text, #id, #name, #input, #to_h).
  class FakeAnthropic
    Block = Struct.new(:type, :text, :id, :name, :input, :extra, keyword_init: true) do
      def to_h = { type: type, text: text, id: id, name: name, input: input }.compact.merge(extra || {})
    end
    Msg = Struct.new(:content, :stop_reason, :stop_details, :usage, keyword_init: true)
    Usage = Struct.new(:input_tokens, :output_tokens)

    attr_reader :requests

    def initialize(*replies)
      @replies = replies
      @requests = []
    end

    def beta = self
    def messages = self

    def create(**params)
      @requests << params
      @replies.shift
    end

    def self.reply(*blocks, stop: :end_turn, usage: [ 300, 90 ])
      Msg.new(content: blocks, stop_reason: stop, stop_details: nil, usage: Usage.new(*usage))
    end

    def self.text(text) = Block.new(type: :text, text: text)
    def self.tool_use(id, name, input) = Block.new(type: :tool_use, id: id, name: name, input: input)
    def self.thinking = Block.new(type: :thinking, extra: { thinking: "", signature: "sig" })
  end
end

RSpec.describe Ai::AnthropicConverse do
  before { stub_const("FakeAnthropic", AnthropicConverseSpec::FakeAnthropic) }

  let(:center) { create(:center) }

  it "answers a forced tool call with a strict structured output and returns it as the tool's input" do
    sdk = FakeAnthropic.new(FakeAnthropic.reply(FakeAnthropic.thinking,
                                                FakeAnthropic.text('{"reasoning":"Warm.","tone":5,"clarity":4}')))
    original = Ai::Bedrock.instance_variable_get(:@client)
    Ai::Bedrock.client = described_class.new(client: sdk)

    result = Ai::Bedrock.structured(model: "claude-sonnet-5-5", system: "Grade it.", prompt: "Draft",
                                    tool: Evals::Judge::TOOL, temperature: 0)

    expect(result.input).to eq("reasoning" => "Warm.", "tone" => 5, "clarity" => 4)
    expect(result.cost_micros).to eq(Ai::Bedrock.cost_micros("claude-sonnet-5-5", 300, 90))
    request = sdk.requests.first
    expect(request).not_to include(:tools, :tool_choice, :temperature)
    schema = request.dig(:output_config, :format_, :schema)
    expect(schema[:required]).to eq(%w[reasoning tone clarity])
    expect(schema[:additionalProperties]).to be(false)
    expect(schema.dig(:properties, :tone)).to eq(type: "integer")
    expect(request[:fallbacks]).to eq("default")
  ensure
    Ai::Bedrock.client = original
  end

  it "keeps Haiku drafts off the fallback beta" do
    sdk = FakeAnthropic.new(FakeAnthropic.reply(FakeAnthropic.text('{"subject":"Hi","body":"Hello","policy_citations":[]}')))
    described_class.new(client: sdk).converse(
      model_id: "claude-haiku-5-5", system: [ { text: "s" } ], messages: [ { role: "user", content: [ { text: "p" } ] } ],
      tool_config: { tools: [ { tool_spec: Drafting::Prompt::TOOL } ], tool_choice: { tool: { name: "submit_draft" } } }
    )
    expect(sdk.requests.first).not_to include(:fallbacks, :betas)
  end

  it "runs the Ask Cubby tool loop, sending tool results and unknown blocks back unchanged" do
    create(:family, center: center, name: "Effertz family", primary_guardian_name: "Roman Effertz")
    sdk = FakeAnthropic.new(
      FakeAnthropic.reply(FakeAnthropic.thinking, FakeAnthropic.tool_use("toolu_1", "find_family", { "name" => "Effertz" }),
                          stop: :tool_use, usage: [ 200, 40 ]),
      FakeAnthropic.reply(FakeAnthropic.text("The Effertz family is enrolled."), usage: [ 260, 30 ])
    )

    answer = Agent::AskCubby.new(center: center, client: described_class.new(client: sdk), model: "claude-sonnet-5-5")
                            .call("Tell me about Effertz")

    expect(answer.text).to eq("The Effertz family is enrolled.")
    expect(answer.steps).to eq([ { tool: "find_family", input: { "name" => "Effertz" } } ])
    expect([ answer.input_tokens, answer.output_tokens ]).to eq([ 460, 70 ])

    first, second = sdk.requests
    expect(first[:tools].map { |t| t[:name] }).to include("find_family", "search_policies")
    expect(first[:thinking]).to eq(type: :between_tools)
    assistant, results = second[:messages].last(2)
    expect(assistant[:content]).to eq([
      { type: :thinking, thinking: "", signature: "sig" },
      { type: "tool_use", id: "toolu_1", name: "find_family", input: { "name" => "Effertz" } }
    ])
    expect(results[:role]).to eq("user")
    expect(results[:content].first).to include(type: "tool_result", tool_use_id: "toolu_1")
    expect(JSON.parse(results[:content].first[:content])["families"].size).to eq(1)
  end

  it "raises Ai::Bedrock::Error on a refusal and on unparseable structured output" do
    refusal = FakeAnthropic.reply(stop: :refusal)
    refusal.stop_details = Struct.new(:category).new(:cyber)
    broken = FakeAnthropic.reply(FakeAnthropic.text("{not json"), stop: :max_tokens)
    call = lambda do |sdk|
      described_class.new(client: sdk).converse(
        model_id: "claude-haiku-5-5", messages: [ { role: "user", content: [ { text: "p" } ] } ],
        tool_config: { tools: [ { tool_spec: Drafting::Prompt::TOOL } ], tool_choice: { tool: { name: "submit_draft" } } }
      )
    end

    expect { call.(FakeAnthropic.new(refusal)) }.to raise_error(Ai::Bedrock::Error, /declined.*cyber/)
    expect { call.(FakeAnthropic.new(broken)) }.to raise_error(Ai::Bedrock::Error, /not valid JSON.*max_tokens/)
  end

  it "closes schemas by keyword, not by property name, and passes tool errors through" do
    sdk = FakeAnthropic.new(FakeAnthropic.reply(FakeAnthropic.text('{"minimum":"x","count":3,"tags":[{"label":"a"}]}')),
                            FakeAnthropic.reply(FakeAnthropic.text("ok")))
    converse = described_class.new(client: sdk)
    spec = { name: "submit", description: "d", input_schema: { json: {
      type: "object", properties: {
        minimum: { type: "string" }, count: { type: "integer", minimum: 0 },
        tags: { type: "array", items: { type: "object", properties: { label: { type: "string" } } } }
      }
    } } }
    converse.converse(model_id: "claude-haiku-5-5", messages: [ { role: "user", content: [ { text: "p" } ] } ],
                      tool_config: { tools: [ { tool_spec: spec } ], tool_choice: { tool: { name: "submit" } } })
    schema = sdk.requests.first.dig(:output_config, :format_, :schema)
    expect(schema[:properties].keys).to eq(%i[minimum count tags])
    expect(schema[:properties][:count]).to eq(type: "integer")
    expect(schema.dig(:properties, :tags, :items)).to include(additionalProperties: false, required: %w[label])

    converse.converse(model_id: "claude-haiku-5-5", messages: [
      { role: "user", content: [ { tool_result: { tool_use_id: "t1", status: "error", content: [ { json: { error: "boom" } } ] } } ] }
    ])
    expect(sdk.requests.last[:messages].first[:content].first).to eq(type: "tool_result", tool_use_id: "t1",
                                                                     content: '{"error":"boom"}', is_error: true)
  end
end
