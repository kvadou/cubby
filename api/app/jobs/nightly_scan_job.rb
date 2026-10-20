# Fired by sidekiq-cron each night; fans out one ScanCenterJob per center (record D15).
class NightlyScanJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 1

  def perform
    args = Center.find_each.map { |c| [ c.id, c.today.iso8601 ] }
    ScanCenterJob.perform_bulk(args) if args.any?
  end
end
