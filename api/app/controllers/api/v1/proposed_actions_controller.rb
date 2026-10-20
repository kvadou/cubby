module Api
  module V1
    # The director's queue. Decisions go through ProposedAction's guarded transitions; the client sends
    # the lock_version it last saw, and a stale one is a 409 carrying the current row (D6).
    class ProposedActionsController < BaseController
      MAX_BODY = 5_000
      MAX_REASON = 500
      MAX_SNOOZE = 30.days
      CLOSED_LIST_LIMIT = 200

      rescue_from ProposedAction::InvalidTransition, ActiveRecord::StaleObjectError do
        render json: { error: "conflict", message: "Someone else already handled this.",
                       action: serialize([ proposed_action.reload ]).first }, status: :conflict
      end

      def index
        scope = current_center.proposed_actions
        scope = case params[:status]
        when nil, "inbox" then scope.inbox.order(:kind, :detected_at)
        when "proposed" then scope.proposed.order(:kind, :detected_at)
        when *ProposedAction::STATUSES then scope.where(status: params[:status]).order(decided_at: :desc).limit(CLOSED_LIST_LIMIT)
        else scope.none
        end
        scope = scope.where(kind: params[:kind]) if ProposedAction::KINDS.include?(params[:kind])

        render json: serialize(scope.to_a)
      end

      def approve
        body = params[:final_body].to_s.strip.presence
        return render_invalid("Write the message before approving.") if proposed_action.family_facing? && body.nil?
        return render_invalid("Keep the message under #{MAX_BODY} characters.") if body.to_s.length > MAX_BODY

        with_client_lock_version { proposed_action.approve!(by: Current.user.actor, final_body: body) }
      end

      def dismiss
        reason = params[:reason].to_s.strip.presence
        return render_invalid("Keep the reason under #{MAX_REASON} characters.") if reason.to_s.length > MAX_REASON

        with_client_lock_version { proposed_action.dismiss!(by: Current.user.actor, reason: reason) }
      end

      def snooze
        until_time = begin
          Time.zone.iso8601(params[:until].to_s)
        rescue ArgumentError
          nil
        end
        unless until_time&.between?(Time.current, MAX_SNOOZE.from_now)
          return render_invalid("Pick a time in the next #{MAX_SNOOZE.inspect}.")
        end

        with_client_lock_version { proposed_action.snooze!(until_time: until_time) }
      end

      private

      def proposed_action
        @proposed_action ||= current_center.proposed_actions.find(params[:id])
      end

      def with_client_lock_version
        version = Integer(params[:lock_version], exception: false)
        return render_invalid("lock_version is required.") if version.nil?

        proposed_action.lock_version = version
        yield
        render json: serialize([ proposed_action ]).first
      end

      def serialize(actions)
        user_ids = actions.filter_map { |a| a.decided_by.to_s[/\Auser:(\d+)\z/, 1] }.uniq
        names = User.where(id: user_ids).pluck(:id, :name).to_h.transform_keys { |id| "user:#{id}" }

        actions.map do |a|
          a.slice(:id, :kind, :status, :resolution, :rationale, :facts, :occurs_on, :detected_at, :last_seen_at,
                  :snoozed_until, :decided_at, :decided_by, :dismiss_reason, :draft_subject, :draft_body,
                  :final_body, :lock_version)
           .merge(subject: { type: a.subject_type, id: a.subject_id }, family_facing: a.family_facing?,
                  decided_by_name: names[a.decided_by])
        end
      end
    end
  end
end
