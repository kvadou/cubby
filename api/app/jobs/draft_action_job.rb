class DraftActionJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(action_id)
    action = ProposedAction.proposed.find_by(id: action_id)
    Drafting::Drafter.new.call(action) if action&.family_facing?
  end
end
