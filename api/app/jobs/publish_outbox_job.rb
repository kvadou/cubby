# Kicked after each committed change and every minute by sidekiq-cron as a backstop.
class PublishOutboxJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 0

  def perform
    Events::Publisher.call
  end
end
