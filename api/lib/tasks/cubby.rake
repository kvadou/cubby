namespace :cubby do
  desc "Chunk and embed every center's handbook now (needs Bedrock access)"
  task "policies:index": :environment do
    PolicyDocument.find_each { |d| puts "#{d.center.name} / #{d.title}: #{Policies::Indexer.call(d, force: ENV['FORCE'] == '1')}" }
  end

  desc "Draft every open family-facing action inline (needs Bedrock access); REDRAFT=1 redoes ready drafts"
  task draft: :environment do
    scope = ProposedAction.proposed.where(kind: ProposedAction::FAMILY_FACING)
    scope = scope.where.not(draft_status: "ready") unless ENV["REDRAFT"] == "1"
    scope.includes(:center).find_each do |a|
      Drafting::Drafter.new.call(a)
      a.reload
      puts "##{a.id} #{a.kind}: #{a.draft_status}#{" (#{a.draft_error})" if a.draft_error}"
    end
  end

  desc "Scan every center now and print what changed (no Sidekiq needed)"
  task scan: :environment do
    Center.find_each do |center|
      result = CenterScan.new(center).call
      puts "#{center.name}: #{result.to_h}"
      center.proposed_actions.inbox.order(:kind, :id).each { |a| puts "  [#{a.kind}] #{a.rationale}" }
    end
  end
end
