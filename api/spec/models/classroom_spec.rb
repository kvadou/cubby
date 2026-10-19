require "rails_helper"

RSpec.describe Classroom, type: :model do
  describe "validations" do
    subject { build(:classroom) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:center_id) }

    it "rejects an age range that runs backwards" do
      room = build(:classroom, age_min_months: 48, age_max_months: 33)
      expect(room).not_to be_valid
      expect(room.errors[:age_max_months]).to be_present
    end

    it "is backed by a database check constraint too" do
      room = create(:classroom)
      expect { room.update_columns(age_max_months: 1) }.to raise_error(ActiveRecord::StatementInvalid, /classroom_age_range/)
    end
  end

  describe "#open_seats" do
    it "counts only enrolled children and never goes negative" do
      room = create(:classroom, capacity: 2)
      create_list(:enrollment, 2, :enrolled, classroom: room)
      create(:enrollment) # waitlisted, no classroom
      expect(room.open_seats).to eq(0)
    end
  end

  describe "#accepts_age?" do
    let(:room) { build(:classroom, age_min_months: 33, age_max_months: 48) }

    it "includes the minimum and excludes the maximum" do
      expect(room.accepts_age?(33)).to be(true)
      expect(room.accepts_age?(47)).to be(true)
      expect(room.accepts_age?(48)).to be(false)
      expect(room.accepts_age?(32)).to be(false)
    end
  end

  describe "#expected_children_on and #staff_required_for" do
    it "counts children scheduled for that weekday and rounds staff up" do
      room = create(:classroom, ratio: 5)
      monday = Date.new(2026, 10, 19)
      create_list(:enrollment, 6, :enrolled, classroom: room, schedule_days: %w[mon wed])
      create_list(:enrollment, 3, :enrolled, classroom: room, schedule_days: %w[tue thu])

      expect(room.expected_children_on(monday)).to eq(6)
      expect(room.staff_required_for(6)).to eq(2)
      expect(room.staff_required_for(5)).to eq(1)
    end
  end
end
