require "rails_helper"

RSpec.describe ProposedAction, type: :model do
  let(:action) { create(:proposed_action) }

  describe "transitions (O4, O5)" do
    it "approves once and writes exactly one history row" do
      expect { action.approve!(by: "renee", final_body: "Hi Jordan") }
        .to change(ProposedActionTransition, :count).by(1)
      expect(action).to be_approved
      expect(action.final_body).to eq("Hi Jordan")
      expect(action.transitions.last).to have_attributes(from_status: "proposed", to_status: "approved", actor: "renee")
    end

    it "refuses to move a closed action again" do
      action.dismiss!(by: "renee", reason: "Already called")
      expect { action.approve!(by: "renee") }.to raise_error(described_class::InvalidTransition)
      expect(action.reload).to be_dismissed
    end

    it "rejects a stale copy that someone else already changed" do
      stale = described_class.find(action.id)
      action.approve!(by: "renee", final_body: "Hi Jordan")
      expect { stale.dismiss!(by: "sam") }.to raise_error(described_class::InvalidTransition)
      expect(ProposedActionTransition.where(proposed_action_id: action.id).count).to eq(1)
    end

    it "won't approve a family-facing action with nothing to send" do
      expect { action.approve!(by: "renee") }.to raise_error(described_class::InvalidTransition, /no message/)
      expect(action.reload).to be_proposed
    end

    it "rolls back the status change if the history row fails" do
      allow(ProposedActionTransition).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect { action.approve!(by: "renee") }.to raise_error(ActiveRecord::RecordInvalid)
      expect(action.reload).to be_proposed
    end

    it "keeps history rows append-only" do
      action.approve!(by: "renee", final_body: "Hi Jordan")
      expect { action.transitions.last.update!(actor: "someone else") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "requires a known resolution, enforced in the database too" do
      expect { action.resolve!(resolution: "whatever") }.to raise_error(ArgumentError)
      expect { action.update_columns(status: "resolved") }
        .to raise_error(ActiveRecord::StatementInvalid, /resolution_only_when_resolved/)
    end
  end

  describe "cooldowns (O6)" do
    it "suppresses the same key after a dismissal until the cooldown ends" do
      action.dismiss!(by: "renee", now: Time.zone.local(2026, 10, 19, 9))
      expect(described_class.suppressed?(action.dedupe_key, Time.zone.local(2026, 10, 25))).to be(true)
      expect(described_class.suppressed?(action.dedupe_key, Time.zone.local(2026, 10, 27))).to be(false)
    end

    it "hides snoozed actions from the inbox without closing them" do
      action.snooze!(until_time: 2.days.from_now)
      expect(described_class.inbox).not_to include(action)
      expect(described_class.inbox(3.days.from_now)).to include(action)
      expect(action.reload).to be_proposed
    end
  end

  describe "facts snapshot (O9)" do
    it "is read only after insert" do
      expect { action.update!(facts: { changed: true }) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect(action.reload.facts).to eq("guardian_first_name" => "Jordan", "total_cents" => 145_000)
    end

    it "rejects contact details" do
      expect(build(:proposed_action, facts: { email: "x" })).not_to be_valid
      expect(build(:proposed_action, facts: { note: "reach me at a@b.co" })).not_to be_valid
    end

    it "digests the same facts identically regardless of key order" do
      expect(described_class.digest({ a: 1, b: 2 })).to eq(described_class.digest({ "b" => 2, "a" => 1 }))
    end
  end

  describe "uniqueness (O3)" do
    it "allows only one proposed row per key, but closed rows can share it" do
      action.dismiss!(by: "renee")
      create(:proposed_action, center: action.center, dedupe_key: action.dedupe_key)
      expect { create(:proposed_action, center: action.center, dedupe_key: action.dedupe_key) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
