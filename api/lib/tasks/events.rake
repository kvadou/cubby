namespace :events do
  desc "Create the local SNS topic, SQS queues, subscription, and S3 bucket in Moto"
  task setup: :environment do
    puts Events::Setup.call.map { |k, v| "#{k}: #{v}" }
  end

  desc "Run the analytics consumer (long-polls SQS until stopped)"
  task consume: :environment do
    $stdout.sync = true
    stop = false
    %w[INT TERM].each { |sig| trap(sig) { stop = true } }
    Events::Consumer.run(stop: -> { stop })
  end

  desc "Publish pending outbox events now"
  task publish: :environment do
    puts "published #{Events::Publisher.call}"
  end
end
