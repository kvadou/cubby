FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "Director #{n}" }
    sequence(:email_address) { |n| "director#{n}@example.test" }
    password { "correct horse battery" }
  end
end
