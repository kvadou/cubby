require "rails_helper"

RSpec.describe Invoice, type: :model do
  let(:today) { Date.new(2026, 10, 19) }

  it "requires paid_at when paid" do
    expect(build(:invoice, status: "paid", paid_at: nil)).not_to be_valid
  end

  it "rejects zero and negative amounts" do
    expect(build(:invoice, amount_cents: 0)).not_to be_valid
  end

  describe ".past_due" do
    it "returns open invoices due before the given day" do
      overdue = create(:invoice, due_on: today - 8)
      create(:invoice, due_on: today) # due today, not late yet
      create(:invoice, due_on: today - 30, status: "paid", paid_at: 1.day.ago)
      create(:invoice, due_on: today - 30, status: "void")

      expect(described_class.past_due(today)).to contain_exactly(overdue)
    end
  end

  it "reports days past due only for open, late invoices" do
    expect(build(:invoice, due_on: today - 18).days_past_due(today)).to eq(18)
    expect(build(:invoice, due_on: today + 3).days_past_due(today)).to eq(0)
    expect(build(:invoice, due_on: today - 18, status: "paid", paid_at: 1.day.ago).days_past_due(today)).to eq(0)
  end
end
