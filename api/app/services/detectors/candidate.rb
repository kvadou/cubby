module Detectors
  # What a detector found. The scan turns candidates into ProposedAction rows.
  Candidate = Data.define(:kind, :subject, :dedupe_key, :rationale, :facts, :occurs_on, :detector_version) do
    def digest
      ProposedAction.digest(facts)
    end
  end
end
