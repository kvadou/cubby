module Evals
  # LLM grader for what code can't check: tone and clarity. A different model from the drafter grades,
  # reasons before scoring, and uses a fixed rubric (docs/prior-art/2026-10-19-phase4-ai.md, D3).
  module Judge
    SYSTEM = <<~TEXT.freeze
      You grade a draft message from a child care center director to a family. Be strict and specific.

      Rubric, each 1 to 5:
      - tone: 5 = warm, respectful, assumes good faith, no pressure or guilt; 3 = polite but stiff or a
        little pushy; 1 = cold, threatening, or condescending.
      - clarity: 5 = a busy parent knows exactly what is being asked and what to do next; 3 = the ask is
        there but buried or vague; 1 = unclear what the family should do.
      First write your reasoning, then the scores.
    TEXT

    TOOL = {
      name: "submit_grade",
      description: "Submit the grade for the draft.",
      input_schema: { json: {
        type: "object", additionalProperties: false, required: %w[reasoning tone clarity],
        properties: {
          reasoning: { type: "string" },
          tone: { type: "integer", minimum: 1, maximum: 5 },
          clarity: { type: "integer", minimum: 1, maximum: 5 }
        }
      } }
    }.freeze

    module_function

    def grade(llm, purpose:, draft:, model: Ai::Bedrock::MODELS[:judge])
      prompt = "Purpose of the message: #{purpose}\n\n<draft>\nSubject: #{draft['subject']}\n\n#{draft['body']}\n</draft>"
      result = llm.structured(model: model, system: SYSTEM, prompt: prompt, tool: TOOL, max_tokens: 800, temperature: 0)
      { "tone" => result.input["tone"].to_i, "clarity" => result.input["clarity"].to_i,
        "reasoning" => result.input["reasoning"].to_s, "cost_micros" => result.cost_micros.to_i }
    end
  end
end
