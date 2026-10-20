class DraftActionJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  # If every retry fails, say so instead of leaving the card on "Drafting…" forever.
  sidekiq_retries_exhausted do |job, error|
    ProposedAction.where(id: job["args"].first, status: "proposed", draft_status: "pending")
                  .update_quietly(draft_status: "failed", draft_error: "Drafting stopped after retries: #{error.message}".first(500))
  end

  def perform(action_id)
    action = ProposedAction.proposed.find_by(id: action_id)
    Drafting::Drafter.new.call(action) if action&.family_facing?
  end
end
