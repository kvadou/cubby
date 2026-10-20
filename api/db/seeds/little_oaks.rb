# One realistic, fictional center. Every date is relative to today so the data stays believable
# whenever it is re-seeded, and it is shaped so the detectors have real work to find:
# open seats with stale waitlist entries, a few past-due invoices, and one understaffed room tomorrow.
#
# Idempotent: does nothing if the center already exists. `bin/rails db:seed:replant` rebuilds it.

return if Rails.env.test?
return if Center.exists?(name: "Little Oaks Early Learning")

Faker::Config.random = Random.new(42)
Faker::Config.locale = "en-US"
rng = Random.new(42)
today = Date.current

def weekday_on_or_after(date)
  date += 1 while date.saturday? || date.sunday?
  date
end

ActiveRecord::Base.transaction do
  center = Center.create!(name: "Little Oaks Early Learning", city: "Minneapolis",
                          timezone: "America/Chicago", director_name: "Renee Albright")

  rooms = {
    acorns:   center.classrooms.create!(name: "Acorns",   age_min_months: 6,  age_max_months: 16, capacity: 8,  ratio: 4),
    saplings: center.classrooms.create!(name: "Saplings", age_min_months: 16, age_max_months: 33, capacity: 14, ratio: 7),
    maples:   center.classrooms.create!(name: "Maples",   age_min_months: 33, age_max_months: 48, capacity: 20, ratio: 10),
    oaks:     center.classrooms.create!(name: "Oaks",     age_min_months: 48, age_max_months: 72, capacity: 20, ratio: 10)
  }
  # Monthly tuition per classroom, in cents.
  tuition = { acorns: 1_950_00, saplings: 1_750_00, maples: 1_450_00, oaks: 1_350_00 }
  # Enrolled children per room: two rooms keep open seats so the waitlist has somewhere to go.
  enrolled_targets = { acorns: 8, saplings: 12, maples: 17, oaks: 20 }

  languages = %w[en en en en en en es es so hmn]
  families = []
  new_family = lambda do
    last = Faker::Name.unique.last_name
    guardian = "#{Faker::Name.first_name} #{last}"
    families << center.families.create!(
      name: "#{last} family", primary_guardian_name: guardian,
      email: "#{guardian.parameterize(separator: '.')}@example.com",
      phone: "(612) 555-#{format('%04d', rng.rand(100..9999))}",
      preferred_language: languages.sample(random: rng)
    )
    families.last
  end
  birthdate_for = ->(room) { today << rng.rand(room.age_min_months + 1...room.age_max_months - 1) }
  part_time = [ %w[mon wed fri], %w[tue thu], %w[mon tue wed thu] ]

  # Enrolled children. About one in six joins an existing family as a sibling.
  enrolled = []
  enrolled_targets.each do |key, count|
    room = rooms[key]
    count.times do
      family = families.any? && rng.rand < 0.17 ? families.sample(random: rng) : new_family.call
      child = family.children.create!(first_name: Faker::Name.first_name, last_name: family.name.delete_suffix(" family"),
                                      birthdate: birthdate_for.call(room))
      days = rng.rand < 0.2 ? part_time.sample(random: rng) : Enrollment::DAYS
      child.enrollments.create!(status: "enrolled", classroom: room, schedule_days: days,
                                enrolled_on: today - rng.rand(30..540), requested_start_on: nil)
      enrolled << [ child, key ]
    end
  end

  # Waitlist: ages spread across rooms, some contacted recently, most gone quiet.
  waitlist_specs = [
    [ :acorns, 45, nil ], [ :acorns, 8, nil ], [ :saplings, 31, 30 ], [ :saplings, 19, 3 ],
    [ :saplings, 62, 40 ], [ :maples, 27, nil ], [ :maples, 16, 16 ], [ :maples, 4, nil ],
    [ :oaks, 38, 10 ], [ :oaks, 90, 60 ]
  ]
  waitlist_specs.each do |key, days_waiting, contacted_days_ago|
    family = new_family.call
    child = family.children.create!(first_name: Faker::Name.first_name, last_name: family.name.delete_suffix(" family"),
                                    birthdate: birthdate_for.call(rooms[key]))
    child.enrollments.create!(status: "waitlisted", waitlisted_at: days_waiting.days.ago,
                              requested_start_on: today + rng.rand(7..60),
                              last_contacted_at: contacted_days_ago&.days&.ago)
  end

  # Staff: a lead per room, assistants, a floater, and the director.
  staff = { director: center.staff_members.create!(name: "Renee Albright", role: "director") }
  rooms.each_key do |key|
    staff[:"#{key}_lead"] = center.staff_members.create!(name: Faker::Name.name, role: "lead_teacher")
    staff[:"#{key}_assistant"] = center.staff_members.create!(name: Faker::Name.name, role: "assistant_teacher")
  end
  staff[:floater] = center.staff_members.create!(name: Faker::Name.name, role: "floater")

  # Shifts from today through the next five weekdays. Tomorrow the Saplings assistant is out, which leaves
  # the room under ratio: the RatioRisk detector should catch it.
  zone = ActiveSupport::TimeZone[center.timezone]
  day = weekday_on_or_after(today)
  understaffed_day = weekday_on_or_after(today + 1)
  6.times do
    rooms.each_key do |key|
      shifts = [ staff[:"#{key}_lead"] ]
      shifts << staff[:"#{key}_assistant"] unless day == understaffed_day && key == :saplings
      shifts.each do |member|
        member.staff_shifts.create!(classroom: rooms[key],
                                    starts_at: zone.local(day.year, day.month, day.day, 7, 30),
                                    ends_at: zone.local(day.year, day.month, day.day, 16, 30))
      end
    end
    day = weekday_on_or_after(day + 1)
  end

  # Attendance for the last ten school days, about 92% present on scheduled days.
  school_days = (today - 16...today).select { |d| !d.saturday? && !d.sunday? }.last(10)
  enrolled.each do |child, key|
    enrollment = child.active_enrollment
    school_days.each do |d|
      next unless enrollment.schedule_days.include?(d.strftime("%a").downcase)
      next if rng.rand > 0.92
      child.attendances.create!(classroom: rooms[key], on: d,
                                checked_in_at: zone.local(d.year, d.month, d.day, 7 + rng.rand(0..2), rng.rand(0..59)),
                                checked_out_at: zone.local(d.year, d.month, d.day, 15 + rng.rand(0..2), rng.rand(0..59)))
    end
  end

  # Monthly tuition invoices for the last three months plus next month. Most are paid;
  # five families are past due by different amounts of time.
  invoice_seq = 1000
  months = [ today.prev_month(2), today.prev_month, today, today.next_month ].map(&:beginning_of_month)
  late_families = families.select { |f| f.children.joins(:enrollments).merge(Enrollment.enrolled).exists? }
                          .sample(5, random: rng)
  families.each do |family|
    rooms_for_family = enrolled.select { |c, _| c.family_id == family.id }.map(&:last)
    next if rooms_for_family.empty?
    amount = rooms_for_family.sum { |k| tuition[k] }
    months.each do |m|
      invoice_seq += 1
      due = m
      invoice = family.invoices.new(number: "LO-#{invoice_seq}", amount_cents: amount,
                                    period_start: m, period_end: m.end_of_month, due_on: due)
      if due >= today
        invoice.status = "open"
      elsif late_families.include?(family) && m == today.beginning_of_month
        invoice.status = "open"
      elsif late_families.first == family && m == today.prev_month.beginning_of_month
        invoice.status = "open" # one family is two months behind
      else
        invoice.status = "paid"
        invoice.paid_at = zone.local(due.year, due.month, due.day, 9) + rng.rand(0..5).days
      end
      invoice.save!
    end
  end

  puts "Seeded #{center.name}: #{center.classrooms.count} classrooms, #{families.size} families, " \
       "#{Child.count} children (#{Enrollment.waitlisted.count} waitlisted), #{StaffMember.count} staff, " \
       "#{Invoice.count} invoices (#{Invoice.past_due.count} past due), #{Attendance.count} attendance records."
end
