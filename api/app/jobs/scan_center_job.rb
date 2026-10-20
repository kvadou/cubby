# Scans one center. Safe to retry or run twice: CenterScan is idempotent (record O1-O3).
class ScanCenterJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 3

  def perform(center_id, as_of = nil)
    center = Center.find_by(id: center_id)
    return unless center

    date = as_of ? Date.iso8601(as_of) : center.today
    result = CenterScan.new(center, as_of: date).call
    Rails.logger.info("scan center=#{center_id} as_of=#{date} #{result.to_h.to_json}")
  end
end
