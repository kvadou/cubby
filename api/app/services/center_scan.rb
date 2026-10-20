# Runs every detector for one center and reconciles the queue with what they see (record D2, D5, D6, D15):
# - new condition: insert a proposed row (the partial unique index makes concurrent scans safe)
# - same condition, same facts: refresh last_seen_at
# - same condition, new facts: resolve the old row as superseded and insert a fresh one
# - condition gone: resolve as condition_cleared (or expired for a past ratio date)
# - recently approved or dismissed: skip until its cooldown ends
class CenterScan
  DETECTORS = [ Detectors::StaleWaitlist, Detectors::PastDueInvoice, Detectors::RatioRisk ].freeze
  Result = Data.define(:created, :refreshed, :superseded, :resolved, :suppressed)

  def initialize(center, as_of: center.today, now: Time.current)
    @center = center
    @as_of = as_of
    @now = now
  end

  def call
    totals = Hash.new(0)
    DETECTORS.each do |detector|
      counts = scan(detector)
      counts.each { |k, v| totals[k] += v }
    end
    Result.new(**Result.members.index_with { |m| totals[m] })
  end

  private

  def scan(detector)
    counts = Hash.new(0)
    ProposedAction.transaction do
      # One scan per center and detector at a time; the unique index is the backstop if this is bypassed.
      lock_key = "cubby:scan:#{@center.id}:#{detector::KIND}"
      ProposedAction.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{ProposedAction.connection.quote(lock_key)}))")

      candidates = detector.new(@center, as_of: @as_of).call
      open_rows = @center.proposed_actions.proposed.where(kind: detector::KIND).index_by(&:dedupe_key)
      inserts = []

      candidates.each do |candidate|
        existing = open_rows.delete(candidate.dedupe_key)
        if existing && existing.facts_digest == candidate.digest
          existing.update_columns(last_seen_at: @now)
          counts[:refreshed] += 1
        elsif existing
          existing.resolve!(resolution: "superseded", now: @now)
          counts[:superseded] += 1
          inserts << row_for(candidate)
        elsif ProposedAction.suppressed?(candidate.dedupe_key, @now)
          counts[:suppressed] += 1
        else
          inserts << row_for(candidate)
        end
      end

      counts[:created] += insert(inserts)

      open_rows.each_value do |row|
        resolution = row.occurs_on && row.occurs_on <= @as_of ? "expired" : "condition_cleared"
        row.resolve!(resolution: resolution, now: @now)
        counts[:resolved] += 1
      end
    end
    counts
  end

  def row_for(candidate)
    record = ProposedAction.new(center: @center, kind: candidate.kind, subject: candidate.subject,
                                dedupe_key: candidate.dedupe_key, rationale: candidate.rationale,
                                facts: candidate.facts, facts_digest: candidate.digest,
                                detector_version: candidate.detector_version, occurs_on: candidate.occurs_on,
                                detected_at: @now, last_seen_at: @now)
    record.validate!
    record.attributes.except("id", "created_at", "updated_at").merge("created_at" => @now, "updated_at" => @now)
  end

  def insert(rows)
    return 0 if rows.empty?

    result = ProposedAction.insert_all(rows, unique_by: :one_open_action_per_key, returning: %i[id kind])
    ids = result.rows.map(&:first)
    if ids.any?
      ProposedActionTransition.insert_all(ids.map { |id|
        { proposed_action_id: id, from_status: nil, to_status: "proposed", actor: "scan", created_at: @now }
      })
      OutboxEvent.record_all!("action.proposed", center_id: @center.id, occurred_at: @now,
                              payloads: result.rows.map { |id, kind| { action_id: id, kind: kind, proposed_at: @now.iso8601(6) } })
    end
    ids.size
  end
end
