class ExportDomainEventsJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(date = nil)
    return unless Events.enabled?

    Events::Exporter.call(date ? Date.iso8601(date) : Time.now.utc.to_date - 1)
  end
end
