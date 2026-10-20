require "rails_helper"

RSpec.describe Drafting::Checks do
  let(:facts) { { guardian_first_name: "Roman", total_cents: 270_000, invoice_numbers: %w[LO-1162 LO-1163] } }
  let(:fee_policy) { Drafting::Prompt::Excerpt.new(id: "P1", title: "Late payments and late fees", body: "A late fee of $35 is added on the 10th.") }
  let(:plan_policy) { Drafting::Prompt::Excerpt.new(id: "P2", title: "Payment plans", body: "Any family can ask for a payment plan.") }
  let(:excerpts) { [ fee_policy, plan_policy ] }
  let(:good_body) do
    "Hi Roman,\n\nI wanted to reach out about tuition. Our records show $2,700.00 open across invoices LO-1162 and " \
      "LO-1163. If this month is tight, you can ask me about a payment plan that splits the balance into smaller " \
      "payments alongside regular tuition, and we will find something that works for your family. If you've " \
      "already sent payment, thank you, and please disregard this note. Just reply here with any questions.\n\n" \
      "Warmly,\nRenee Albright"
  end

  def run(body, citations: [ "P2" ], subject: "Tuition balance")
    described_class.run(kind: "past_due_invoice", facts: facts, director_name: "Renee Albright", excerpts: excerpts,
                        draft: { "subject" => subject, "body" => body, "policy_citations" => citations })
  end

  it "passes a sourced, plain, well-formed draft" do
    expect(described_class.failures(run(good_body))).to be_empty
  end

  it "fails an amount that is neither in the facts nor in a cited policy" do
    checks = run(good_body.sub("payment plan", "payment plan with a $50 discount"))
    expect(checks["no_unsupported_amounts"].first).to be(false)
  end

  it "allows a policy amount only when that policy is cited" do
    body = good_body.sub("If you've", "A $35 late fee applies after the 10th. If you've")
    expect(run(body, citations: %w[P2])["no_unsupported_amounts"].first).to be(false)
    expect(run(body, citations: %w[P2])["fees_cited"].first).to be(false)
    expect(described_class.failures(run(body, citations: %w[P1 P2]))).to be_empty
  end

  it "requires the balance to be stated" do
    expect(run(good_body.sub("$2,700.00", "a balance"))["states_balance"].first).to be(false)
  end

  it "rejects citations of excerpts it was not given" do
    expect(run(good_body, citations: %w[P9])["citations_valid"].first).to be(false)
  end

  it "rejects contact details, markdown, and placeholders" do
    expect(run(good_body.sub("Just reply", "Email renee@littleoaks.test or reply"))["no_contact_details"].first).to be(false)
    expect(run(good_body.sub("Just reply", "Call (612) 555-0100 or reply"))["no_contact_details"].first).to be(false)
    expect(run(good_body.sub("I wanted", "**I wanted"))["plain_text"].first).to be(false)
    expect(run(good_body.sub("Warmly", "[Your name]"))["plain_text"].first).to be(false)
  end

  it "checks greeting, sign-off, length, and subject" do
    expect(run(good_body.sub("Hi Roman", "Hello there"))["greets_guardian"].first).to be(false)
    expect(run(good_body.sub("Renee Albright", "The front desk"))["signed_by_director"].first).to be(false)
    expect(run("Hi Roman, pay $2,700.00. Renee")["length"].first).to be(false)
    expect(run(good_body, subject: "")["subject"].first).to be(false)
  end

  it "requires waitlist drafts to name the child and the room" do
    checks = described_class.run(kind: "stale_waitlist", director_name: "Renee Albright", excerpts: [],
                                 facts: { guardian_first_name: "Lindsy", child_first_name: "Marjory", classroom_name: "Maples" },
                                 draft: { "subject" => "A seat", "body" => "Hi Lindsy, a seat opened. Renee", "policy_citations" => [] })
    expect(checks["names_child_and_room"].first).to be(false)
  end
end
