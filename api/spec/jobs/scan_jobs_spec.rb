require "rails_helper"

RSpec.describe "scan jobs" do
  it "fans out one ScanCenterJob per center (O14)" do
    centers = create_list(:center, 3)
    NightlyScanJob.new.perform
    expect(ScanCenterJob.jobs.map { |j| j["args"].first }).to match_array(centers.map(&:id))
  end

  it "scans the given center and date" do
    center = create(:center)
    create(:invoice, family: create(:family, center: center), due_on: Date.new(2026, 10, 9))
    ScanCenterJob.new.perform(center.id, "2026-10-19")
    expect(center.proposed_actions.proposed.count).to eq(1)
  end

  it "ignores a center that no longer exists" do
    expect { ScanCenterJob.new.perform(0) }.not_to raise_error
  end

  it "registers the nightly cron entry" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    expect(schedule["nightly_scan"]).to include("class" => "NightlyScanJob", "cron" => "0 4 * * * America/Chicago")
  end
end
