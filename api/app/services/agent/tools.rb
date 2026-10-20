module Agent
  # Read-only tools for "Ask Cubby", all scoped to one center. No tool writes, sends, or returns
  # contact details (docs/prior-art/2026-10-19-phase4-ai.md, D6).
  class Tools
    def self.spec(name, description, properties = {}, required = [])
      { tool_spec: { name: name, description: description,
                     input_schema: { json: { type: "object", properties: properties, required: required } } } }
    end

    SPECS = [
      spec("find_family", "Find families by family name, guardian first name, or child first name. Returns children " \
                          "with age, enrollment status and classroom, and open invoices.",
           { name: { type: "string" } }, %w[name]),
      spec("classroom_staffing", "Capacity, open seats, children expected, teachers scheduled, and teachers required " \
                                 "by ratio for every classroom on a date (default today).",
           { date: { type: "string", description: "YYYY-MM-DD" } }),
      spec("waitlist", "Children on the waitlist with age, requested start date, days waiting, and days since contact.",
           { classroom_name: { type: "string", description: "Only children whose age fits this classroom" } }),
      spec("search_policies", "Search the center's family handbook. Returns the most relevant sections.",
           { query: { type: "string" } }, %w[query]),
      spec("open_actions", "The director's current queue of proposed actions.")
    ].freeze

    def initialize(center)
      @center = center
    end

    def run(name, input)
      input = input.to_h.stringify_keys
      case name
      when "find_family" then find_family(input["name"].to_s)
      when "classroom_staffing" then classroom_staffing(input["date"])
      when "waitlist" then waitlist(input["classroom_name"])
      when "search_policies" then search_policies(input["query"].to_s)
      when "open_actions" then open_actions
      else { error: "unknown tool #{name}" }
      end
    rescue Date::Error
      { error: "dates look like 2026-10-20" }
    end

    private

    attr_reader :center

    def today = center.today

    def money(cents) = ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)

    def find_family(name)
      return { error: "give a name" } if name.strip.length < 2

      q = "%#{ActiveRecord::Base.sanitize_sql_like(name.strip)}%"
      families = center.families.left_joins(:children)
                       .where("families.name ILIKE :q OR families.primary_guardian_name ILIKE :q OR children.first_name ILIKE :q", q: q)
                       .distinct.limit(5).includes(:invoices, children: { enrollments: :classroom })
      return { families: [], note: "no family matches #{name}" } if families.empty?

      { families: families.map do |f|
        {
          family: f.name, guardian_first_name: f.guardian_first_name, preferred_language: f.preferred_language,
          children: f.children.map do |c|
            e = c.enrollments.find { |x| x.status != "withdrawn" }
            { first_name: c.first_name, age_months: c.age_in_months(today), status: e&.status, classroom: e&.classroom&.name }
          end,
          open_invoices: f.invoices.select { |i| i.status == "open" }.sort_by(&:due_on).map do |i|
            { number: i.number, amount: money(i.amount_cents), due_on: i.due_on, days_past_due: [ i.days_past_due(today), 0 ].max }
          end
        }
      end }
    end

    def classroom_staffing(date)
      date = date.present? ? Date.iso8601(date) : today
      { date: date, classrooms: center.classrooms.order(:age_min_months).map do |r|
        expected = r.expected_children_on(date)
        { name: r.name, ages_months: "#{r.age_min_months}-#{r.age_max_months}", capacity: r.capacity, open_seats: r.open_seats,
          children_expected: expected, teachers_scheduled: r.staff_shifts.on_date(date).count, teachers_required: r.staff_required_for(expected) }
      end }
    end

    def waitlist(classroom_name)
      room = classroom_name.present? ? center.classrooms.find_by("name ILIKE ?", classroom_name.strip) : nil
      return { error: "no classroom named #{classroom_name}" } if classroom_name.present? && room.nil?

      rows = Enrollment.waitlisted.joins(child: :family).where(families: { center_id: center.id }).includes(:child)
                       .order(:waitlisted_at).map do |e|
        age = e.child.age_in_months(e.requested_start_on || today)
        next if room && !room.accepts_age?(age)

        { child: e.child.first_name, age_months_at_start: age, requested_start_on: e.requested_start_on,
          days_waiting: e.days_on_waitlist, days_since_contact: e.last_contacted_at && (today - e.last_contacted_at.to_date).to_i }
      end
      { waitlist: rows.compact }
    end

    def search_policies(query)
      { sections: Policies::Search.call(center, query).map { |c| { heading: c.heading, text: c.body } } }
    end

    def open_actions
      { actions: center.proposed_actions.inbox.order(:kind, :detected_at).map { |a| { kind: a.kind, summary: a.rationale } } }
    end
  end
end
