redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6380/0") }

Sidekiq.configure_server do |config|
  config.redis = redis
  config.on(:startup) do
    schedule = Rails.root.join("config/schedule.yml")
    Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(schedule)) if schedule.exist?
  end
end

Sidekiq.configure_client { |config| config.redis = redis }
