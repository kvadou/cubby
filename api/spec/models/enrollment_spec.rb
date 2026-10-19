require "rails_helper"

RSpec.describe Enrollment, type: :model do
  it "requires a classroom once enrolled" do
    enrollment = build(:enrollment, status: "enrolled", classroom: nil)
    expect(enrollment).not_to be_valid
    expect(enrollment.errors[:classroom]).to be_present
  end

  it "allows only one active enrollment per child" do
    child = create(:child)
    create(:enrollment, child: child)
    duplicate = build(:enrollment, child: child)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:child]).to include("already has an active enrollment")
  end

  it "enforces one active enrollment in the database as well" do
    child = create(:child)
    create(:enrollment, child: child)
    duplicate = build(:enrollment, child: child)
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows a new enrollment after the old one is withdrawn" do
    child = create(:child)
    create(:enrollment, child: child, status: "withdrawn", withdrawn_on: Date.current)
    expect(build(:enrollment, child: child)).to be_valid
  end

  it "rejects weekend or misspelled schedule days" do
    enrollment = build(:enrollment, schedule_days: %w[mon sat])
    expect(enrollment).not_to be_valid
    expect(enrollment.errors[:schedule_days].first).to include("sat")
  end

  it "counts whole days on the waitlist" do
    enrollment = build(:enrollment, waitlisted_at: 10.days.ago - 3.hours)
    expect(enrollment.days_on_waitlist).to eq(10)
  end
end
