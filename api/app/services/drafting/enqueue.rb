module Drafting
  # Queues a draft for every open family-facing action that has none yet. Called after each scan.
  module Enqueue
    module_function

    def enabled? = ENV.fetch("CUBBY_AI_DRAFTS", Rails.env.test? ? "off" : "on") == "on"

    def for_center(center)
      return 0 unless enabled?

      ids = center.proposed_actions.proposed.where(kind: ProposedAction::FAMILY_FACING, draft_status: "none").pluck(:id)
      return 0 if ids.empty?

      ProposedAction.where(id: ids, draft_status: "none").update_quietly(draft_status: "pending")
      DraftActionJob.perform_bulk(ids.map { |id| [ id ] })
      ids.size
    end
  end
end
