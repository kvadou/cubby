require "rails_helper"

RSpec.describe Drafting::Drafter do
  let(:center) { create(:center, name: "Little Oaks", director_name: "Renee Albright") }
  let(:family) { create(:family, center: center, primary_guardian_name: "Roman Effertz") }
  let!(:action) do
    facts = { guardian_first_name: "Roman", total_cents: 270_000, invoice_numbers: %w[LO-1162], oldest_due_on: "2026-09-01",
              max_days_past_due: 48, preferred_language: "en" }
    create(:proposed_action, center: center, subject: family, facts: facts, facts_digest: ProposedAction.digest(facts))
  end
  let(:document) { center.policy_documents.create!(title: "Family handbook", body: "## Payment plans\nAsk for a plan.\n\n## Late payments and late fees\nA late fee of $35 applies.") }
  let(:good) do
    { subject: "Your tuition balance", policy_citations: [ "P1" ],
      body: "Hi Roman,\n\nOur records show $2,700.00 open on invoice LO-1162. If this month is tight, you can ask " \
            "me about a payment plan that spreads the balance over a few payments alongside regular tuition, and we " \
            "will find something that works for your family. If you've already paid, thank you, and please ignore " \
            "this note. Reply here any time with questions.\n\nWarmly,\nRenee Albright" }
  end

  before do
    # The query embeds nearest to "Payment plans", so it becomes P1.
    allow(Ai::Bedrock).to receive(:embed).and_return(axis_vector(0))
    document.chunks.create!(center: center, position: 1, heading: "Payment plans", body: "Ask for a plan.", embedding: axis_vector(0))
    document.chunks.create!(center: center, position: 2, heading: "Late payments and late fees", body: "A late fee of $35 applies.", embedding: axis_vector(1))
  end

  it "stores a passing draft with its citations, usage, and cost, without bumping lock_version" do
    llm = BedrockHelpers::FakeLlm.new(good)
    described_class.new(llm: llm, model: "us.anthropic.claude-haiku-4-5-20251001-v1:0").call(action)
    action.reload

    expect(action.draft_status).to eq("ready")
    expect(action.draft_body).to start_with("Hi Roman")
    expect(action.draft_citations).to eq([ { "chunk_id" => document.chunks.first.id, "heading" => "Payment plans" } ])
    expect(action.draft_checks.values).to all(be(true))
    expect([ action.draft_input_tokens, action.draft_output_tokens, action.draft_cost_micros ]).to eq([ 400, 150, 1150 ])
    expect(action.lock_version).to eq(0)
    expect(llm.prompts.first).to include("<facts>", '"total_cents": 270000', %(<policy id="P1" title="Payment plans">))
  end

  it "retries once with the failed checks as feedback" do
    llm = BedrockHelpers::FakeLlm.new(good.merge(body: good[:body].sub("$2,700.00", "$2,000.00")), good)
    described_class.new(llm: llm).call(action)

    expect(llm.prompts.size).to eq(2)
    expect(llm.prompts.last).to include("failed these checks", "no_unsupported_amounts", "states_balance")
    expect(action.reload.draft_status).to eq("ready")
    expect(action.draft_input_tokens).to eq(800)
  end

  it "marks the draft failed when the retry also fails, keeping the reasons" do
    bad = good.merge(body: good[:body].sub("$2,700.00", "$2,000.00"))
    described_class.new(llm: BedrockHelpers::FakeLlm.new(bad, bad)).call(action)

    expect(action.reload.draft_status).to eq("failed")
    expect(action.draft_error).to include("states_balance")
  end

  it "records a Bedrock outage as a failed draft instead of raising" do
    described_class.new(llm: BedrockHelpers::FakeLlm.new(Ai::Bedrock::Error.new("throttled"))).call(action)
    expect(action.reload).to have_attributes(draft_status: "failed", draft_error: "throttled")
  end

  it "marks a draft failed when Sidekiq gives up, instead of leaving it pending" do
    ProposedAction.where(id: action.id).update_quietly(draft_status: "pending")
    DraftActionJob.sidekiq_retries_exhausted_block.call({ "args" => [ action.id ] }, StandardError.new("timeout"))
    expect(action.reload).to have_attributes(draft_status: "failed", lock_version: 0)
    expect(action.draft_error).to include("timeout")
  end

  it "does not touch an action the director already decided" do
    action.dismiss!(by: "user:1")
    described_class.new(llm: BedrockHelpers::FakeLlm.new(good)).call(action)
    expect(action.reload.draft_status).to eq("none")
  end
end
