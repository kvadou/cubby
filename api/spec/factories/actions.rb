FactoryBot.define do
  factory :proposed_action do
    center
    kind { "past_due_invoice" }
    subject { association(:family, center: center) }
    sequence(:dedupe_key) { |n| "past_due_invoice:family:#{n}" }
    rationale { "Owes tuition" }
    facts { { guardian_first_name: "Jordan", total_cents: 145_000 } }
    facts_digest { ProposedAction.digest(facts) }
    detector_version { 1 }
    detected_at { Time.current }
    last_seen_at { Time.current }
  end
end
