module BedrockHelpers
  # A real SDK client in stub mode: it validates every request against the Bedrock API model.
  def stub_bedrock_client
    Aws::BedrockRuntime::Client.new(stub_responses: true, region: "us-east-1",
                                    credentials: Aws::Credentials.new("test", "test"))
  end

  def tool_use_response(name, input, input_tokens: 100, output_tokens: 50)
    { output: { message: { role: "assistant", content: [ { tool_use: { tool_use_id: "tu_#{SecureRandom.hex(4)}", name: name, input: input } } ] } },
      stop_reason: "tool_use", usage: { input_tokens: input_tokens, output_tokens: output_tokens, total_tokens: input_tokens + output_tokens },
      metrics: { latency_ms: 1 } }
  end

  def text_response(text)
    { output: { message: { role: "assistant", content: [ { text: text } ] } }, stop_reason: "end_turn",
      usage: { input_tokens: 80, output_tokens: 20, total_tokens: 100 }, metrics: { latency_ms: 1 } }
  end

  # Unit vectors along one axis, so cosine nearest neighbors are predictable.
  def axis_vector(i)
    Array.new(1024, 0.0).tap { |v| v[i] = 1.0 }
  end

  # Stand-in for Ai::Bedrock in drafter specs: returns queued drafts and records prompts.
  class FakeLlm
    attr_reader :prompts

    def initialize(*drafts)
      @drafts = drafts
      @prompts = []
    end

    def structured(model:, prompt:, **)
      @prompts << prompt
      draft = @drafts.shift or raise "FakeLlm ran out of drafts"
      raise draft if draft.is_a?(Exception)

      Ai::Bedrock::Result.new(input: draft.deep_stringify_keys, model: model, input_tokens: 400, output_tokens: 150,
                              cost_micros: Ai::Bedrock.cost_micros(model, 400, 150))
    end
  end
end

RSpec.configure do |config|
  config.include BedrockHelpers
  config.around do |example|
    original = Ai::Bedrock.instance_variable_get(:@client)
    example.run
  ensure
    Ai::Bedrock.client = original
  end
end
