module Ai
  # Speaks the slice of Bedrock's Converse API that Cubby uses, backed by the Anthropic API, so the drafter,
  # judge, and agent run unchanged when AI_PROVIDER=anthropic. Requests are translated to Messages API
  # shapes and responses come back as Converse-shaped structs.
  #
  # A forced tool call (tool_choice: { tool: }) becomes a structured output: current Sonnet models reject
  # forced tool_choice, and output_config.format guarantees schema-valid JSON, which is what Cubby forced
  # the tool for. The JSON comes back as a tool_use block so callers can't tell the difference.
  class AnthropicConverse
    Response = Data.define(:output, :usage, :stop_reason)
    Output = Data.define(:message)
    Message = Data.define(:content)
    Usage = Data.define(:input_tokens, :output_tokens)
    ToolUse = Data.define(:tool_use_id, :name, :input)

    # One content block. `raw` keeps blocks Converse has no shape for (thinking) so the agent loop can send
    # them back unchanged on the next turn.
    Block = Data.define(:text, :tool_use, :raw) do
      def to_h
        return { text: text } if text
        return { tool_use: { tool_use_id: tool_use.tool_use_id, name: tool_use.name, input: tool_use.input } } if tool_use

        { anthropic_raw: raw }
      end
    end

    # Refusals on these models are retried server-side on a model that accepts the request.
    FALLBACK_MODELS = /sonnet-5-5|opus-5/
    THINKING_HEADROOM = 8000

    def initialize(client: Anthropic::Client.new(api_key: ENV.fetch("ANTHROPIC_API_KEY"), timeout: 30, max_retries: 1))
      @client = client
    end

    def converse(model_id:, messages:, system: [], inference_config: {}, tool_config: nil)
      # Converse budgets cover the reply alone; on these models thinking counts toward max_tokens too.
      params = { model: model_id, max_tokens: inference_config.fetch(:max_tokens, 1000) + THINKING_HEADROOM,
                 system_: system.map { |s| s[:text] }.join("\n\n"), messages: messages.map { |m| message(m) },
                 output_config: { effort: :medium } }
      forced = tool_config&.dig(:tool_choice, :tool, :name)
      spec = forced && tool_config[:tools].map { |t| t[:tool_spec] }.find { |s| s[:name] == forced }

      if spec
        params[:output_config][:format_] = { type: :json_schema, schema: strict_schema(spec[:input_schema][:json]) }
      elsif tool_config
        params[:tools] = tool_config[:tools].map { |t| tool(t[:tool_spec]) }
        # Tool loops send history back each turn; no thinking means no thinking blocks to carry.
        params[:thinking] = { type: :between_tools } if model_id.match?(/sonnet-5-5/)
      end
      if model_id.match?(FALLBACK_MODELS)
        params[:betas] = [ "server-side-fallback-2026-07-01" ]
        params[:fallbacks] = "default"
      end

      response(@client.beta.messages.create(**params), forced)
    end

    private

    def message(m)
      { role: m[:role].to_s, content: m[:content].map { |c| block_param(c) } }
    end

    def block_param(c)
      if c[:text] then { type: "text", text: c[:text] }
      elsif (use = c[:tool_use]) then { type: "tool_use", id: use[:tool_use_id], name: use[:name], input: use[:input] || {} }
      elsif (result = c[:tool_result])
        content = result[:content].map { |r| r.key?(:json) ? r[:json].to_json : r[:text].to_s }.join
        { type: "tool_result", tool_use_id: result[:tool_use_id], content: content, is_error: result[:status].to_s == "error" }
      elsif c[:anthropic_raw] then c[:anthropic_raw]
      else raise ArgumentError, "unsupported content block #{c.keys.inspect}"
      end
    end

    def tool(spec)
      { name: spec[:name], description: spec[:description], input_schema: spec[:input_schema][:json] }
    end

    # Structured outputs need every object closed with all its properties required, and don't take numeric
    # bounds; the prompts and Cubby's checks still enforce those. Walks schema keywords only, so a property
    # that happens to be named "minimum" is left alone.
    def strict_schema(schema)
      schema = schema.symbolize_keys
      schema = schema.except(:minimum, :maximum) if %w[integer number].include?(schema[:type].to_s)
      schema[:items] = strict_schema(schema[:items]) if schema[:items].is_a?(Hash)
      if schema[:type].to_s == "object"
        props = (schema[:properties] || {}).to_h { |name, sub| [ name, strict_schema(sub) ] }
        schema = schema.merge(properties: props, additionalProperties: false, required: props.keys.map(&:to_s))
      end
      schema
    end

    def response(msg, forced)
      if msg.stop_reason.to_s == "refusal"
        raise Ai::Bedrock::Error, "model declined the request (#{msg.stop_details&.category || 'no category'})"
      end

      blocks = msg.content.filter_map do |b|
        case b.type.to_s
        when "text" then Block.new(text: b.text, tool_use: nil, raw: nil)
        when "tool_use"
          Block.new(text: nil, tool_use: ToolUse.new(tool_use_id: b.id, name: b.name, input: b.input.to_h), raw: nil)
        else Block.new(text: nil, tool_use: nil, raw: b.to_h)
        end
      end
      blocks = [ structured_block(blocks, forced, msg.stop_reason) ] if forced
      Response.new(output: Output.new(message: Message.new(content: blocks)),
                   usage: Usage.new(input_tokens: msg.usage.input_tokens, output_tokens: msg.usage.output_tokens),
                   stop_reason: msg.stop_reason.to_s)
    end

    def structured_block(blocks, name, stop_reason)
      json = blocks.filter_map(&:text).join
      input = JSON.parse(json)
      Block.new(text: nil, tool_use: ToolUse.new(tool_use_id: "structured", name: name, input: input), raw: nil)
    rescue JSON::ParserError
      raise Ai::Bedrock::Error, "structured output was not valid JSON (stop reason #{stop_reason})"
    end
  end
end
