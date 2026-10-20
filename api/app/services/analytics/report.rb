module Analytics
  # Center metrics computed only from received domain events, so the page shows what the pipeline
  # actually delivered (docs/prior-art/2026-10-19-phase5-events.md, D5).
  class Report
    WINDOWS = [ 7, 30, 90 ].freeze
    KINDS = ProposedAction::KINDS

    def initialize(center, days:, now: Time.current)
      @center = center
      @days = days
      @now = now
      @since = (now - days.days).beginning_of_day
    end

    def to_h
      {
        days: @days,
        since: @since,
        totals: totals,
        by_kind: by_kind,
        median_hours_to_decision: median_hours(decisions),
        messages: messages,
        ai: ai,
        daily: daily,
        pipeline: pipeline
      }
    end

    private

    def events
      @events ||= DomainEvent.for_center(@center).where(occurred_at: @since..@now).to_a
    end

    def of(type) = events.select { |e| e.event_type == type }
    def decisions = events.select { |e| %w[action.approved action.dismissed].include?(e.event_type) }

    def totals
      approved, dismissed = of("action.approved").size, of("action.dismissed").size
      { proposed: of("action.proposed").size, approved: approved, dismissed: dismissed,
        resolved: of("action.resolved").size, snoozed: of("action.snoozed").size,
        approval_rate: approved + dismissed > 0 ? (approved.to_f / (approved + dismissed)).round(3) : nil }
    end

    def by_kind
      KINDS.map do |kind|
        mine = events.select { |e| e.payload["kind"] == kind }
        count = ->(type) { mine.count { |e| e.event_type == type } }
        { kind: kind, proposed: count.("action.proposed"), approved: count.("action.approved"),
          dismissed: count.("action.dismissed"), resolved: count.("action.resolved"),
          median_hours_to_decision: median_hours(mine.select { |e| %w[action.approved action.dismissed].include?(e.event_type) }) }
      end
    end

    def median_hours(list)
      hours = list.filter_map do |e|
        proposed, decided = e.payload.values_at("proposed_at", "decided_at")
        begin
          ((Time.iso8601(decided.to_s) - Time.iso8601(proposed.to_s)) / 3600.0) if proposed && decided
        rescue ArgumentError
          nil # a malformed event shouldn't take the page down
        end
      end.sort
      return nil if hours.empty?

      mid = hours.size / 2
      (hours.size.odd? ? hours[mid] : (hours[mid - 1] + hours[mid]) / 2.0).round(1)
    end

    def messages
      sources = of("action.approved").select { |e| e.payload["family_facing"] }.map { |e| e.payload["message_source"] }
      { approved: sources.size, draft_as_is: sources.count("draft_as_is"), draft_edited: sources.count("draft_edited"),
        starter_or_own: sources.count("starter_or_own") }
    end

    def ai
      drafts = of("draft.completed")
      cost = drafts.sum { |e| e.payload["cost_micros"].to_i }
      approved_messages = messages[:approved]
      { drafts: drafts.size, drafts_ready: drafts.count { |e| e.payload["status"] == "ready" },
        cost_micros: cost,
        cost_per_approved_message_micros: drafts.any? && approved_messages.positive? ? (cost / approved_messages) : nil }
    end

    def daily
      tz = ActiveSupport::TimeZone[@center.timezone]
      days = (@since.in_time_zone(tz).to_date..@now.in_time_zone(tz).to_date).to_a.last(@days)
      grouped = decisions.group_by { |e| e.occurred_at.in_time_zone(tz).to_date }
      days.map do |d|
        list = grouped[d] || []
        { date: d, approved: list.count { |e| e.event_type == "action.approved" }, dismissed: list.count { |e| e.event_type == "action.dismissed" } }
      end
    end

    def pipeline
      { waiting_to_publish: OutboxEvent.unpublished.where(center: @center).count,
        last_received_at: DomainEvent.for_center(@center).maximum(:received_at) }
    end
  end
end
