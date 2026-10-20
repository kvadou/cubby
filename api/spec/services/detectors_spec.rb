require "rails_helper"

RSpec.describe "Detectors" do
  let(:center) { create(:center) }

  describe Detectors::PastDueInvoice do
    it "fires from the morning after the due date, one action per family (O10)" do
      family = create(:family, center: center)
      create(:invoice, family: family, number: "A", due_on: ScanHelpers::MONDAY, amount_cents: 100_00)
      create(:invoice, family: family, number: "B", due_on: ScanHelpers::MONDAY - 31, amount_cents: 200_00)

      expect(described_class.new(center, as_of: ScanHelpers::MONDAY).call.map(&:facts))
        .to contain_exactly(include(invoice_numbers: [ "B" ]))
      found = described_class.new(center, as_of: ScanHelpers::TUESDAY).call
      expect(found.size).to eq(1)
      expect(found.first.facts).to include(invoice_numbers: %w[B A], total_cents: 300_00, max_days_past_due: 32)
    end

    it "uses the center's local date, not UTC, at the day boundary (O10)" do
      create(:invoice, family: create(:family, center: center), due_on: ScanHelpers::MONDAY)
      # 03:00 UTC Tuesday is still 22:00 Monday in Chicago, so a Monday-due invoice is not late yet.
      travel_to(Time.utc(2026, 10, 20, 3)) do
        expect(center.today).to eq(ScanHelpers::MONDAY)
        expect(described_class.new(center, as_of: center.today).call).to be_empty
      end
      travel_to(Time.utc(2026, 10, 20, 6)) do
        expect(described_class.new(center, as_of: center.today).call.size).to eq(1)
      end
    end

    it "keeps contact details out of the facts (O9)" do
      create(:invoice, family: create(:family, center: center), due_on: ScanHelpers::MONDAY - 10)
      facts = described_class.new(center, as_of: ScanHelpers::MONDAY).call.first.facts
      expect(facts.keys.join(" ")).not_to match(/email|phone/)
    end
  end

  describe Detectors::StaleWaitlist do
    let(:room) { create(:classroom, center: center, age_min_months: 33, age_max_months: 48, capacity: 2) }
    let(:now) { ScanHelpers::MONDAY.in_time_zone("America/Chicago").change(hour: 12) }

    def waitlist(age_months:, waited:, contacted: nil, start_in: 10)
      child = create(:child, family: create(:family, center: center), birthdate: ScanHelpers::MONDAY << age_months)
      create(:enrollment, child: child, waitlisted_at: now - waited.days, last_contacted_at: contacted && now - contacted.days,
                          requested_start_on: start_in && ScanHelpers::MONDAY + start_in)
    end

    before { travel_to(now) }

    it "flags quiet families with an open age-appropriate seat (O11)" do
      room
      hit = waitlist(age_months: 36, waited: 30, contacted: 20)
      waitlist(age_months: 36, waited: 30, contacted: 13)           # contacted recently
      waitlist(age_months: 36, waited: 10)                          # not quiet long enough
      waitlist(age_months: 20, waited: 40)                          # no room for this age
      waitlist(age_months: 36, waited: 40, start_in: 90)            # starts too far out

      found = described_class.new(center, as_of: ScanHelpers::MONDAY).call
      expect(found.map(&:subject)).to eq([ hit ])
      expect(found.first.facts).to include(classroom_name: room.name, days_since_contact: 20)
    end

    it "matches the room by the child's age at the requested start date (O11)" do
      room
      # 32 months today, 33 by the requested start in 40 days, so Maples (33-48) fits.
      hit = waitlist(age_months: 32, waited: 30, start_in: 40)
      expect(described_class.new(center, as_of: ScanHelpers::MONDAY).call.map(&:subject)).to eq([ hit ])
    end

    it "stays quiet when the matching room is full (O11)" do
      2.times { enroll(room, birthdate: ScanHelpers::MONDAY << 36) }
      waitlist(age_months: 36, waited: 40)
      expect(described_class.new(center, as_of: ScanHelpers::MONDAY).call).to be_empty
    end
  end

  describe Detectors::RatioRisk do
    let(:room) { create(:classroom, center: center, age_min_months: 16, age_max_months: 33, capacity: 14, ratio: 7) }
    let(:lead) { create(:staff_member, center: center, role: "lead_teacher") }

    it "looks at the next weekday" do
      expect(described_class.next_operating_day(Date.new(2026, 10, 23))).to eq(Date.new(2026, 10, 26))
    end

    it "flags a room short on teaching staff and ignores the director (O12)" do
      9.times { enroll(room, birthdate: ScanHelpers::TUESDAY << 24) }
      shift_for(lead, room, ScanHelpers::TUESDAY)
      shift_for(create(:staff_member, center: center, role: "director"), room, ScanHelpers::TUESDAY)

      found = described_class.new(center, as_of: ScanHelpers::MONDAY).call
      expect(found.size).to eq(1)
      expect(found.first.facts).to include(expected_children: 9, teaching_staff: 1, staff_required: 2, ratio_applied: 7)
      expect(found.first.dedupe_key).to eq("ratio_risk:classroom:#{room.id}:2026-10-20")
    end

    it "counts only children scheduled that weekday" do
      9.times { enroll(room, birthdate: ScanHelpers::TUESDAY << 24, days: %w[mon wed fri]) }
      shift_for(lead, room, ScanHelpers::TUESDAY)
      expect(described_class.new(center, as_of: ScanHelpers::MONDAY).call).to be_empty
    end

    it "applies the youngest child's Minnesota ratio and group size (O13)" do
      mixed = create(:classroom, center: center, age_min_months: 12, age_max_months: 40, capacity: 30, ratio: 10)
      enroll(mixed, birthdate: ScanHelpers::TUESDAY << 14) # an infant sets 1:4 and a group of 8
      8.times { enroll(mixed, birthdate: ScanHelpers::TUESDAY << 36) }
      3.times { shift_for(create(:staff_member, center: center), mixed, ScanHelpers::TUESDAY) }

      facts = described_class.new(center, as_of: ScanHelpers::MONDAY).call.first.facts
      expect(facts).to include(mn_category: "infant", ratio_applied: 4, staff_required: 3, over_group_size: true,
                               group_size_limit: 8)
    end
  end
end
