module Drafting
  # Deterministic checks every draft must pass before a director sees it, and the first layer of the
  # eval suite (docs/prior-art/2026-10-19-phase4-ai.md, D3). Each returns [passed, detail].
  module Checks
    MONEY = /\$\s?\d[\d,]*(?:\.\d{2})?/
    EMAIL = /[\w.+-]+@[\w-]+\.[\w.]+/
    PHONE = /\(?\b\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}\b/
    MARKDOWN = /(\*\*|__|^#+\s|^\s*[-*]\s|\[[^\]]*\])/

    module_function

    # draft: { "subject", "body", "policy_citations" }; excerpts: Prompt::Excerpt list given to the model.
    def run(kind:, facts:, director_name:, excerpts:, draft:)
      facts = facts.to_h.deep_stringify_keys
      body = draft["body"].to_s
      cited = excerpts.select { |e| Array(draft["policy_citations"]).include?(e.id) }
      checks = {
        "greets_guardian" => check(body.first(80).include?(facts["guardian_first_name"].to_s), "opens with the guardian's first name"),
        "signed_by_director" => check(body.last(80).include?(director_name.to_s.split.first.to_s), "signs off with the director"),
        "citations_valid" => citations_valid(draft, excerpts),
        "no_unsupported_amounts" => no_unsupported_amounts(body, facts, cited),
        "fees_cited" => fees_cited(body, cited),
        "no_contact_details" => check(!body.match?(EMAIL) && !body.match?(PHONE), "no email addresses or phone numbers"),
        "plain_text" => check(!body.match?(MARKDOWN), "no markdown, bullets, or bracket placeholders"),
        "length" => check(body.split.size.between?(50, 200), "#{body.split.size} words (50 to 200)"),
        "subject" => check(draft["subject"].to_s.strip.length.between?(1, 80), "subject present and under 80 characters")
      }
      case kind
      when "past_due_invoice"
        checks["states_balance"] = check(amounts(body).include?(facts["total_cents"].to_i), "states the open balance")
      when "stale_waitlist"
        checks["names_child_and_room"] = check(
          body.include?(facts["child_first_name"].to_s) && body.include?(facts["classroom_name"].to_s),
          "names the child and the classroom"
        )
      end
      checks
    end

    def failures(checks) = checks.reject { |_, (ok, _)| ok }.map { |name, (_, detail)| "#{name} (#{detail})" }

    def check(ok, detail) = [ ok, detail ]

    # Dollar amounts in text, as cents.
    def amounts(text)
      text.scan(MONEY).map { |m| (m.delete("$, ").to_f * 100).round }
    end

    def citations_valid(draft, excerpts)
      ids = Array(draft["policy_citations"])
      unknown = ids - excerpts.map(&:id)
      check(unknown.empty?, unknown.empty? ? "cites only provided excerpts" : "cites unknown #{unknown.join(', ')}")
    end

    # Every amount must come from the facts or from an excerpt the draft cites.
    def no_unsupported_amounts(body, facts, cited)
      allowed = [ facts["total_cents"] ].compact.map(&:to_i) + cited.flat_map { |e| amounts(e.body) }
      extra = amounts(body) - allowed
      check(extra.empty?, extra.empty? ? "every amount is sourced" : "unsourced amounts #{extra.map { |c| format('$%.2f', c / 100.0) }.join(', ')}")
    end

    def fees_cited(body, cited)
      return check(true, "mentions no fee") unless body.match?(/\bfees?\b/i)

      check(cited.any? { |e| e.body.match?(/\bfees?\b/i) }, "a fee is mentioned, so a fee policy is cited")
    end
  end
end
