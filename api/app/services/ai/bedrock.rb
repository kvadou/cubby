module Ai
  # Thin wrapper over Bedrock Runtime (docs/prior-art/2026-10-19-phase4-ai.md). Credentials come
  # from the default AWS chain: AWS_PROFILE=cubby locally, a pod role on EKS. Specs swap in a stub
  # client with `Ai::Bedrock.client = Aws::BedrockRuntime::Client.new(stub_responses: true)`.
  #
  # AI_PROVIDER=anthropic swaps the client for Ai::AnthropicConverse, which answers the same Converse
  # calls from the Anthropic API. It has no embedding model, so handbook search falls back to full text.
  module Bedrock
    PROVIDER = ENV["AI_PROVIDER"].presence || "bedrock"

    MODELS = if PROVIDER == "anthropic"
      {
        draft: ENV.fetch("ANTHROPIC_DRAFT_MODEL", "claude-haiku-5-5"),
        agent: ENV.fetch("ANTHROPIC_AGENT_MODEL", "claude-sonnet-5-5"),
        judge: ENV.fetch("ANTHROPIC_JUDGE_MODEL", "claude-sonnet-5-5"),
        embed: nil
      }
    else
      {
        draft: ENV.fetch("BEDROCK_DRAFT_MODEL", "us.anthropic.claude-haiku-4-5-20251001-v1:0"),
        agent: ENV.fetch("BEDROCK_AGENT_MODEL", "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        judge: ENV.fetch("BEDROCK_JUDGE_MODEL", "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        embed: ENV.fetch("BEDROCK_EMBED_MODEL", "amazon.titan-embed-text-v2:0")
      }
    end.freeze

    # USD per million tokens, [input, output]. Check against AWS Bedrock pricing when models change.
    PRICES = { /haiku-4-5/ => [ 1.0, 5.0 ], /sonnet-4-5/ => [ 3.0, 15.0 ],
               /haiku-5-5/ => [ 0.1, 0.5 ], /sonnet-5-5/ => [ 2.0, 10.0 ] }.freeze

    Result = Data.define(:input, :model, :input_tokens, :output_tokens, :cost_micros)

    class Error < StandardError; end

    TRANSIENT = AWS_TRANSIENT_ERRORS + [ Anthropic::Errors::APIError ]

    module_function

    def client
      # Short timeouts and one retry keep a web request or a job from hanging on a slow model call.
      @client ||= if PROVIDER == "anthropic"
        raise Error, "ANTHROPIC_API_KEY is not set" if ENV["ANTHROPIC_API_KEY"].blank?

        AnthropicConverse.new
      else
        Aws::BedrockRuntime::Client.new(region: ENV.fetch("AWS_REGION", "us-east-1"),
                                        http_open_timeout: 5, http_read_timeout: 30, retry_limit: 1)
      end
    end

    def embeddings?
      MODELS[:embed].present?
    end

    def client=(value)
      @client = value
    end

    # Millionths of a dollar: tokens times dollars-per-million-tokens.
    def cost_micros(model, input_tokens, output_tokens)
      price = PRICES.find { |pattern, _| model.match?(pattern) }&.last
      price && ((input_tokens * price[0]) + (output_tokens * price[1])).round
    end

    def embed(text)
      raise Error, "#{PROVIDER} has no embedding model" unless embeddings?

      body = { inputText: text.to_s.first(20_000), dimensions: 1024, normalize: true }.to_json
      resp = client.invoke_model(model_id: MODELS[:embed], content_type: "application/json",
                                 accept: "application/json", body: body)
      JSON.parse(resp.body.read).fetch("embedding")
    rescue *TRANSIENT => e
      raise Error, "embedding failed: #{e.message}"
    end

    # Forces the model to reply by calling `tool`, so the answer arrives as schema-shaped JSON.
    def structured(model:, system:, prompt:, tool:, max_tokens: 1200, temperature: 0.4)
      resp = client.converse(
        model_id: model,
        system: [ { text: system } ],
        messages: [ { role: "user", content: [ { text: prompt } ] } ],
        inference_config: { max_tokens: max_tokens, temperature: temperature },
        tool_config: { tools: [ { tool_spec: tool } ], tool_choice: { tool: { name: tool[:name] } } }
      )
      use = resp.output.message.content.filter_map(&:tool_use).find { |t| t.name == tool[:name] }
      raise Error, "model did not call #{tool[:name]} (stop reason #{resp.stop_reason})" unless use

      usage = resp.usage
      Result.new(input: use.input.to_h.deep_stringify_keys, model: model, input_tokens: usage.input_tokens,
                 output_tokens: usage.output_tokens, cost_micros: cost_micros(model, usage.input_tokens, usage.output_tokens))
    rescue *TRANSIENT => e
      raise Error, e.message
    end
  end
end
