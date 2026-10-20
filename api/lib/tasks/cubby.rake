namespace :cubby do
  desc "Scan every center now and print what changed (no Sidekiq needed)"
  task scan: :environment do
    Center.find_each do |center|
      result = CenterScan.new(center).call
      puts "#{center.name}: #{result.to_h}"
      center.proposed_actions.inbox.order(:kind, :id).each { |a| puts "  [#{a.kind}] #{a.rationale}" }
    end
  end
end
