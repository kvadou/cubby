module Drafting
  # Drafts the family message for one proposed action: retrieve policy excerpts, ask Claude through a
  # forced tool call, run the deterministic checks, and retry once with the failures as feedback. A draft
  # that still fails is stored as failed, and the director starts from Cubby's plain starting text.
  class Drafter
    Draft = Data.define(:input, :checks, :excerpts, :calls)

    def initialize(llm: Ai::Bedrock, model: Ai::Bedrock::MODELS[:draft])
      @llm = llm
      @model = model
    end

    def call(action)
      excerpts = excerpts_for(action)
      prompt = Prompt.new(kind: action.kind, facts: action.facts, center_name: action.center.name,
                          director_name: action.center.director_name, excerpts: excerpts)
      draft = generate(prompt)
      store(action, draft)
    rescue Ai::Bedrock::Error => e
      write(action, draft_status: "failed", draft_error: e.message.first(500), draft_model: @model)
    end

    def generate(prompt)
      calls = []
      text = prompt.user
      2.times do
        result = @llm.structured(model: @model, system: prompt.system, prompt: text, tool: Prompt::TOOL)
        calls << result
        checks = Checks.run(kind: prompt.kind, facts: prompt.facts, director_name: prompt.director_name,
                            excerpts: prompt.excerpts, draft: result.input)
        failures = Checks.failures(checks)
        return Draft.new(input: result.input, checks: checks, excerpts: prompt.excerpts, calls: calls) if failures.empty? || calls.size == 2

        text = prompt.with_feedback(failures)
      end
    end

    private

    def excerpts_for(action)
      chunks = Prompt.queries_for(action.kind, action.facts)
                     .flat_map { |q| Policies::Search.call(action.center, q) }.uniq(&:id)
      @chunk_ids = {}
      chunks.each_with_index.map do |c, i|
        id = "P#{i + 1}"
        @chunk_ids[id] = c.id
        Prompt::Excerpt.new(id: id, title: c.heading, body: c.body)
      end
    end

    def store(action, draft)
      failures = Checks.failures(draft.checks)
      citations = draft.excerpts.select { |e| Array(draft.input["policy_citations"]).include?(e.id) }
                       .map { |e| { "chunk_id" => @chunk_ids[e.id], "heading" => e.title } }
      write(action,
            draft_status: failures.empty? ? "ready" : "failed",
            draft_subject: draft.input["subject"].to_s.first(200),
            draft_body: draft.input["body"].to_s,
            draft_citations: citations,
            draft_checks: draft.checks.transform_values(&:first),
            draft_error: failures.empty? ? nil : "Failed checks: #{failures.join('; ')}".first(500),
            draft_model: @model,
            draft_input_tokens: draft.calls.sum(&:input_tokens),
            draft_output_tokens: draft.calls.sum(&:output_tokens),
            draft_cost_micros: draft.calls.sum { |c| c.cost_micros.to_i })
    end

    # Drafts never bump lock_version: a director mid-review must not get a conflict from a background job.
    def write(action, **attrs)
      ProposedAction.transaction do
        written = ProposedAction.where(id: action.id, status: "proposed").update_quietly(attrs.merge(drafted_at: Time.current))
        next if written.zero?

        OutboxEvent.record!("draft.completed", center_id: action.center_id,
                            payload: action.event_payload(status: attrs[:draft_status], model: attrs[:draft_model],
                                                          cost_micros: attrs[:draft_cost_micros].to_i,
                                                          input_tokens: attrs[:draft_input_tokens].to_i,
                                                          output_tokens: attrs[:draft_output_tokens].to_i))
      end
    end
  end
end
