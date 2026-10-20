namespace :evals do
  desc "Grade AI drafts on golden cases (recorded by default; EVALS_LIVE=1 calls Bedrock and re-records)"
  task drafts: :environment do
    live = ENV["EVALS_LIVE"] == "1"
    run = Evals::DraftSuite.new(live: live).run

    run.results.each do |r|
      failed = r["checks"].reject { |_, ok| ok }.keys
      puts format("%-30s checks %2d/%-2d  tone %d  clarity %d  %s", r["id"], r["checks"].count { |_, ok| ok }, r["checks"].size,
                  r["judge"]["tone"], r["judge"]["clarity"], failed.any? ? "FAILED: #{failed.join(', ')}" : "")
    end
    cost = run.results.sum { |r| r["cost_micros"].to_i } / 1_000_000.0
    puts format("\n%s run: %d cases, checks %d/%d (%.0f%%), judge %.2f/5, model %s%s",
                run.mode, run.cases_total, run.checks_passed, run.checks_total, 100.0 * run.checks_passed / run.checks_total,
                run.judge_score, run.model, live ? format(", cost $%.4f", cost) : "")

    min_rate = ENV.fetch("EVALS_MIN_CHECK_RATE", "0.95").to_f
    min_judge = ENV.fetch("EVALS_MIN_JUDGE", "3.5").to_f
    if run.checks_passed < min_rate * run.checks_total || run.judge_score < min_judge
      abort "Draft evals below threshold (checks >= #{(min_rate * 100).round}%, judge >= #{min_judge})."
    end
  end
end
