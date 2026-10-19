require "rails_helper"

RSpec.describe Child, type: :model do
  describe "#age_in_months" do
    it "only counts a month once the birth day has passed" do
      child = build(:child, birthdate: Date.new(2023, 3, 20))
      expect(child.age_in_months(Date.new(2026, 10, 19))).to eq(42)
      expect(child.age_in_months(Date.new(2026, 10, 20))).to eq(43)
    end
  end
end
