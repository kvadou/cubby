require "rails_helper"

RSpec.describe Evals::DraftSuite do
  let(:dir) { Pathname(Dir.mktmpdir) }

  before { stub_const("Evals::DraftSuite::DIR", dir) }

  after { FileUtils.rm_rf(dir) }

  def write_cases
    dir.join("recordings").mkpath
    dir.join("cases.yml").write(<<~YAML)
      defaults: { center_name: Little Oaks, director_name: Renee Albright }
      cases:
        - id: one
          kind: past_due_invoice
          facts: { guardian_first_name: Roman, total_cents: 270000, invoice_numbers: [LO-1162], preferred_language: en }
          policies: [Payment plans]
          expect: { must_include_any: [[payment plan]], must_not_include: [collections] }
    YAML
  end

  let(:draft) do
    { "subject" => "Tuition", "policy_citations" => [ "P1" ],
      "body" => "Hi Roman,\n\nOur records show $2,700.00 open on invoice LO-1162. If this month is tight, you can ask " \
                "me about a payment plan that spreads the balance over a few payments alongside regular tuition, and " \
                "we will find something that works. If you've already paid, thank you, and please ignore this note. " \
                "Reply here any time with questions.\n\nWarmly,\nRenee Albright" }
  end

  it "records live responses, then replays them and stores the run" do
    write_cases
    allow(Ai::Bedrock).to receive(:structured) do |tool:, model:, **|
      input = tool[:name] == "submit_draft" ? draft : { "reasoning" => "Kind and clear.", "tone" => 5, "clarity" => 4 }
      Ai::Bedrock::Result.new(input: input, model: model, input_tokens: 10, output_tokens: 5, cost_micros: 35)
    end

    live = described_class.new(live: true).run
    expect(dir.join("recordings").glob("*.json").size).to eq(2)

    replay = described_class.new(live: false).run
    expect(Ai::Bedrock).to have_received(:structured).twice
    expect(replay).to have_attributes(mode: "recorded", cases_total: 1, judge_score: 4.5)
    expect(replay.checks_passed).to eq(replay.checks_total)
    expect(replay.checks_total).to eq(live.checks_total)
  end

  it "fails loudly in recorded mode when a prompt has no recording" do
    write_cases
    expect { described_class.new(live: false).run }.to raise_error(Evals::Recorder::MissingRecording, /EVALS_LIVE=1/)
  end
end
