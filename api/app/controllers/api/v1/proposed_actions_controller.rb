module Api
  module V1
    # Read-only inbox for phase 2. Approve, edit and dismiss arrive with authentication in phase 3.
    class ProposedActionsController < BaseController
      def index
        scope = current_center.proposed_actions
        scope = case params[:status]
        when nil, "inbox" then scope.inbox
        when *ProposedAction::STATUSES then scope.where(status: params[:status])
        else scope.none
        end
        scope = scope.where(kind: params[:kind]) if ProposedAction::KINDS.include?(params[:kind])

        render json: scope.order(:kind, :detected_at).map { |a|
          a.slice(:id, :kind, :status, :resolution, :rationale, :facts, :occurs_on, :detected_at,
                  :last_seen_at, :snoozed_until, :decided_at, :decided_by)
           .merge(subject: { type: a.subject_type, id: a.subject_id })
        }
      end
    end
  end
end
