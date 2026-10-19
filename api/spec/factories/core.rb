FactoryBot.define do
  factory :center do
    name { "Test Center" }
    city { "Minneapolis" }
    timezone { "America/Chicago" }
    director_name { "Pat Director" }
  end

  factory :classroom do
    center
    sequence(:name) { |n| "Room #{n}" }
    age_min_months { 33 }
    age_max_months { 48 }
    capacity { 10 }
    ratio { 5 }
  end

  factory :family do
    center
    sequence(:name) { |n| "Family #{n}" }
    primary_guardian_name { "Jordan Rivera" }
    sequence(:email) { |n| "guardian#{n}@example.com" }
  end

  factory :child do
    family
    first_name { "Ada" }
    last_name { "Rivera" }
    birthdate { 40.months.ago.to_date }
  end

  factory :enrollment do
    child
    status { "waitlisted" }
    waitlisted_at { 20.days.ago }

    trait :enrolled do
      status { "enrolled" }
      classroom
      waitlisted_at { nil }
      enrolled_on { 3.months.ago.to_date }
    end
  end

  factory :staff_member do
    center
    name { "Sam Teacher" }
    role { "lead_teacher" }
  end

  factory :staff_shift do
    staff_member
    classroom
    starts_at { Date.current.tomorrow.in_time_zone.change(hour: 7, min: 30) }
    ends_at { Date.current.tomorrow.in_time_zone.change(hour: 16, min: 30) }
  end

  factory :invoice do
    family
    sequence(:number) { |n| "INV-#{n}" }
    amount_cents { 145_000 }
    period_start { Date.current.beginning_of_month }
    period_end { Date.current.end_of_month }
    due_on { Date.current.beginning_of_month }
    status { "open" }
  end
end
