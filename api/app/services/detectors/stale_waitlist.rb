module Detectors
  # A waitlisted family has gone quiet while an age-appropriate seat sits open.
  # No surveyed product automates this (prior-art record D12), so the thresholds are proposals.
  class StaleWaitlist
    KIND = "stale_waitlist"
    VERSION = 1
    QUIET_DAYS = 14
    START_WINDOW_DAYS = 60

    def initialize(center, as_of:)
      @center = center
      @as_of = as_of
      @now = as_of.in_time_zone(center.timezone).end_of_day
    end

    def call
      rooms = @center.classrooms.to_a.select { |r| r.open_seats.positive? }
      return [] if rooms.empty?

      waitlisted.filter_map do |enrollment|
        child = enrollment.child
        # Match on the age the child will be when they start, not today (record O11).
        start = [ enrollment.requested_start_on, @as_of ].compact.max
        age = child.age_in_months(start)
        room = rooms.find { |r| r.accepts_age?(age) }
        next unless room
        next unless quiet?(enrollment)
        next if enrollment.requested_start_on && enrollment.requested_start_on > @as_of + START_WINDOW_DAYS

        last_touch = enrollment.last_contacted_at
        Candidate.new(
          kind: KIND, subject: enrollment, dedupe_key: "#{KIND}:enrollment:#{enrollment.id}",
          rationale: "#{child.first_name} (#{age} months at start) has waited #{enrollment.days_on_waitlist(@now)} days " \
                     "and #{room.name} has #{room.open_seats} open seat#{'s' if room.open_seats > 1}. " \
                     "#{last_touch ? "Last contact was #{days_since(last_touch)} days ago." : 'The family has never been contacted.'}",
          facts: {
            child_first_name: child.first_name,
            age_months: age,
            guardian_first_name: child.family.guardian_first_name,
            preferred_language: child.family.preferred_language,
            days_on_waitlist: enrollment.days_on_waitlist(@now),
            days_since_contact: last_touch && days_since(last_touch),
            classroom_name: room.name,
            open_seats: room.open_seats,
            requested_start_on: enrollment.requested_start_on&.iso8601
          },
          occurs_on: nil, detector_version: VERSION
        )
      end
    end

    private

    def waitlisted
      Enrollment.waitlisted.joins(child: :family).where(families: { center_id: @center.id })
                .includes(child: :family).order(:waitlisted_at)
    end

    def quiet?(enrollment)
      reference = enrollment.last_contacted_at || enrollment.waitlisted_at
      reference <= @now - QUIET_DAYS.days
    end

    def days_since(time)
      ((@now - time) / 1.day).floor
    end
  end
end
