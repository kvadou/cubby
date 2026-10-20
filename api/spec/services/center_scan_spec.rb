require "rails_helper"

RSpec.describe CenterScan do
  let(:center) { create(:center) }
  let(:family) { create(:family, center: center) }
  let!(:invoice) { create(:invoice, family: family, due_on: ScanHelpers::MONDAY - 10) }
  let(:now) { ScanHelpers::MONDAY.in_time_zone("America/Chicago").change(hour: 4) }

  def scan(as_of: ScanHelpers::MONDAY, at: now) = described_class.new(center, as_of: as_of, now: at).call

  it "is idempotent: a second scan creates nothing (O1)" do
    expect(scan.created).to eq(1)
    second = scan
    expect(second.created).to eq(0)
    expect(second.refreshed).to eq(1)
    expect(ProposedAction.proposed.count).to eq(1)
    expect(ProposedActionTransition.count).to eq(1)
  end

  it "resolves an action when the invoice is paid (O7)" do
    scan
    invoice.update!(status: "paid", paid_at: now)
    expect(scan.resolved).to eq(1)
    expect(ProposedAction.last).to have_attributes(status: "resolved", resolution: "condition_cleared")
    expect(ProposedAction.last.transitions.map(&:to_status)).to eq(%w[proposed resolved]) # O5
  end

  it "supersedes an action when the facts change (O8)" do
    first = ProposedAction.find_by!(id: (scan && ProposedAction.last.id))
    create(:invoice, family: family, due_on: ScanHelpers::MONDAY - 3)
    result = scan
    expect(result.superseded).to eq(1)
    expect(first.reload.resolution).to eq("superseded")
    expect(first.transitions.map(&:to_status)).to eq(%w[proposed resolved]) # O5
    expect(ProposedAction.proposed.sole.transitions.map(&:to_status)).to eq(%w[proposed])
    expect(ProposedAction.proposed.sole.facts["invoice_numbers"].size).to eq(2)
  end

  it "respects the dismiss cooldown, then raises it again (O6)" do
    scan
    ProposedAction.last.dismiss!(by: "renee", now: now)
    expect(scan(at: now + 3.days).suppressed).to eq(1)
    expect(scan(at: now + 8.days).created).to eq(1)
  end

  it "stamps the center that owns the subject (O15)" do
    scan
    expect(ProposedAction.last.center_id).to eq(family.center_id)
  end

  it "expires a ratio action once its date has passed" do
    room = create(:classroom, center: center, age_min_months: 16, age_max_months: 33, ratio: 7, capacity: 14)
    8.times { enroll(room, birthdate: ScanHelpers::TUESDAY << 24) }
    scan
    expect(ProposedAction.ratio_risk.proposed.count).to eq(1)
    scan(as_of: ScanHelpers::TUESDAY, at: now + 1.day)
    expect(ProposedAction.ratio_risk.find_by(occurs_on: ScanHelpers::TUESDAY).resolution).to eq("expired")
  end

  context "with concurrent scans against real Postgres (O2)", :concurrency do
    self.use_transactional_tests = false

    after do
      [ ProposedActionTransition, ProposedAction, Invoice, Family, Center ].each(&:delete_all)
    end

    it "leaves exactly one open action" do
      center && invoice # create outside the threads
      threads = 4.times.map do
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { scan } }
      end
      threads.each(&:join)
      expect(ProposedAction.proposed.where(dedupe_key: "past_due_invoice:family:#{family.id}").count).to eq(1)
    end
  end
end
