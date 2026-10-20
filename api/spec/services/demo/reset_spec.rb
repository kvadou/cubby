require "rails_helper"

RSpec.describe Demo::Reset do
  it "empties every table, seeds again, and scans so the inbox has work" do
    old = create(:center, name: "Visitor-edited center")
    user = create(:user, centers: [ old ])
    user.sessions.create!(kind: "cookie")
    seeded = nil

    described_class.new(seed: -> { seeded = create(:center, name: "Little Oaks Early Learning") }).call

    expect(Center.pluck(:name)).to eq([ "Little Oaks Early Learning" ])
    expect(User.count).to eq(0)
    expect(Session.count).to eq(0)
    expect(ActiveRecord::Base.connection.select_value("SELECT count(*) FROM schema_migrations")).to be > 0
    expect(seeded).to be_persisted
  end

  it "never wipes a database that has a real user's address" do
    create(:user, email_address: "director@realcenter.com")
    expect { described_class.new(seed: -> { }).call }.to raise_error(/non-demo users/)
    expect(User.count).to eq(1)
  end

  # Cookies hold the session id, so ids must never be reused after a reset (an old cookie would
  # otherwise resume someone else's new session).
  it "keeps ids increasing across a reset" do
    user = create(:user, email_address: "a@x.test")
    old_id = user.sessions.create!(kind: "cookie").id
    described_class.new(seed: -> { create(:user, email_address: "b@x.test").sessions.create!(kind: "cookie") }).call
    expect(Session.sole.id).to be > old_id
  end

  it "refuses to run outside a demo deployment" do
    allow(Rails.env).to receive(:test?).and_return(false)
    expect { described_class.new(seed: -> { }).call }.to raise_error(/demo deployment/)
  end
end

RSpec.describe DemoResetJob do
  it "does nothing unless this is a demo deployment" do
    expect(Demo::Reset).not_to receive(:new)
    described_class.new.perform
  end

  it "resets in a demo deployment" do
    allow(Demo).to receive(:deployed?).and_return(true)
    reset = instance_double(Demo::Reset, call: nil)
    allow(Demo::Reset).to receive(:new).and_return(reset)
    described_class.new.perform
    expect(reset).to have_received(:call)
  end
end
