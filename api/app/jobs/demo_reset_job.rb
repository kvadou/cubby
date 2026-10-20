# Nightly in a demo deployment (config/schedule.yml): undoes whatever visitors approved, dismissed, or sent.
class DemoResetJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 1

  def perform
    Demo::Reset.new.call if Demo.deployed?
  end
end
