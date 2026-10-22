# Sixty days of past queue activity for the analytics page, written straight to domain_events with the
# same payloads the live pipeline produces, plus demo_history: true so the page can say which days were
# generated. Today's decisions still arrive through the outbox, SNS, and SQS. Fixed random seed, dates
# relative to today, and replaced on every run.
center = Center.find_by!(name: "Little Oaks Early Learning")
DomainEvent.where(center_id: center.id).where("payload @> ?", { demo_history: true }.to_json).delete_all

rng = Random.new(20_261_019)
tz = ActiveSupport::TimeZone[center.timezone]
today = Time.current.in_time_zone(tz).to_date
model = Ai::Bedrock::MODELS[:draft]
action_id = 900_000
rows = []
event = lambda do |type, at, payload|
  rows << { event_id: SecureRandom.uuid, event_type: type, center_id: center.id, occurred_at: at, received_at: at + rng.rand(2..40),
            payload: payload.merge(demo_history: true) }
end
pick = ->(weights) { r = rng.rand * weights.values.sum; weights.find { |_, w| (r -= w) <= 0 }.first }
# Hours from found to decided, by kind: staffing gets handled fast, waitlist calls wait for a quiet moment.
latency = { "ratio_risk" => 0.3..3.0, "past_due_invoice" => 1.5..26.0, "stale_waitlist" => 3.0..44.0 }

(1..60).each do |ago|
  day = today - ago
  next if day.saturday? || day.sunday?

  # Directors got faster as they trusted the queue: fewer edits and quicker decisions in recent weeks.
  trust = 1.0 - (ago / 60.0)
  rng.rand(2..5).times do
    action_id += 1
    kind = pick.({ "past_due_invoice" => 45, "stale_waitlist" => 35, "ratio_risk" => 20 })
    found = tz.local(day.year, day.month, day.day, 6, 0) + rng.rand(0..90).minutes
    base = { action_id: action_id, kind: kind, proposed_at: found.iso8601(6) }
    event.("action.proposed", found, base)

    family_facing = kind != "ratio_risk"
    draft_status = nil
    cost = nil
    if family_facing
      draft_status = rng.rand < 0.92 ? "ready" : "failed"
      input, output = rng.rand(1_400..2_600), rng.rand(180..420)
      cost = Ai::Bedrock.cost_micros(model, input, output).to_i
      event.("draft.completed", found + rng.rand(20..140), base.merge(status: draft_status, model: model, cost_micros: cost,
                                                                     input_tokens: input, output_tokens: output))
    end

    outcome = pick.({ approved: 72, dismissed: 14, resolved: 9, snoozed: 5 })
    hours = rng.rand(latency.fetch(kind)) * (1.3 - (0.5 * trust))
    if outcome == :snoozed
      event.("action.snoozed", found + 1.hour, base.merge(snoozed_until: (found + 1.day).iso8601))
      outcome = :approved
      hours += 24
    end
    decided = [ found + hours.hours, Time.current - 1.hour ].min
    decision = base.merge(decided_at: decided.iso8601(6), decided_by_type: outcome == :resolved ? "scan" : "user")
    case outcome
    when :approved
      source = if !family_facing then "none"
      elsif draft_status != "ready" then "starter_or_own"
      else pick.({ "draft_as_is" => 45 + (25 * trust), "draft_edited" => 45 - (20 * trust), "starter_or_own" => 10 })
      end
      event.("action.approved", decided, decision.merge(family_facing: family_facing, message_source: source,
                                                        draft_status: draft_status, draft_cost_micros: cost))
    when :dismissed then event.("action.dismissed", decided, decision)
    when :resolved then event.("action.resolved", decided, decision)
    end
  end
end

DomainEvent.insert_all!(rows)
