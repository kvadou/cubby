module Evals
  # Runs the golden draft cases through the real prompt, checks, and retry path, then grades tone and
  # clarity with a judge model. `bin/rails evals:drafts` replays recordings; EVALS_LIVE=1 calls Bedrock.
  class DraftSuite
    DIR = Rails.root.join("evals/drafts")
    HANDBOOK = Rails.root.join("db/seeds/policies/little_oaks_family_handbook.md")

    CaseResult = Data.define(:id, :checks, :judge, :draft, :cost_micros)

    def initialize(live: false)
      @live = live
      @recorder = Recorder.new(DIR.join("recordings"), live: live)
      @sections = Policies::Chunker.call(HANDBOOK.read).index_by(&:heading)
      @spec = YAML.load_file(DIR.join("cases.yml"))
    end

    def run
      results = @spec.fetch("cases").map { |c| run_case(c.merge(@spec.fetch("defaults")) { |_, mine, _| mine }) }
      @recorder.prune! if @live
      checks = results.flat_map { |r| r.checks.values }
      scores = results.map { |r| (r.judge["tone"] + r.judge["clarity"]) / 2.0 }
      EvalRun.create!(
        suite: "drafts", mode: @live ? "live" : "recorded", model: Ai::Bedrock::MODELS[:draft], judge_model: Ai::Bedrock::MODELS[:judge],
        cases_total: results.size, checks_passed: checks.count(true), checks_total: checks.size,
        judge_score: (scores.sum / scores.size).round(2),
        results: results.map { |r| r.to_h.transform_keys(&:to_s) }
      )
    end

    private

    def run_case(c)
      excerpts = Array(c["policies"]).each_with_index.map do |heading, i|
        section = @sections.fetch(heading) { raise KeyError, "case #{c['id']}: no handbook section #{heading.inspect}" }
        Drafting::Prompt::Excerpt.new(id: "P#{i + 1}", title: section.heading, body: section.body)
      end
      prompt = Drafting::Prompt.new(kind: c["kind"], facts: c["facts"], center_name: c["center_name"],
                                    director_name: c["director_name"], excerpts: excerpts)
      draft = Drafting::Drafter.new(llm: @recorder).generate(prompt)
      checks = draft.checks.transform_values(&:first).merge(expectations(c["expect"].to_h, draft.input["body"].to_s))
      judge = Judge.grade(@recorder, purpose: Drafting::Prompt::PURPOSES.fetch(c["kind"]), draft: draft.input)
      CaseResult.new(id: c["id"], checks: checks, judge: judge, draft: draft.input,
                     cost_micros: draft.calls.sum { |x| x.cost_micros.to_i } + judge["cost_micros"])
    end

    def expectations(expect, body)
      text = body.downcase
      out = {}
      Array(expect["must_include_any"]).each_with_index do |options, i|
        out["includes_any_#{i + 1}"] = options.any? { |o| text.include?(o.to_s.downcase) }
      end
      Array(expect["must_not_include"]).each do |phrase|
        out["excludes #{phrase}"] = !text.include?(phrase.to_s.downcase)
      end
      out
    end
  end
end
