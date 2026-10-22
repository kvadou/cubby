class DemoVisit < ApplicationRecord
  # Host of the page that sent the visitor to the demo, or nil for direct visits and anything malformed.
  def self.record!(referrer)
    uri = URI.parse(referrer.to_s.first(500))
    host = uri.host if uri.is_a?(URI::HTTP)
    create!(referrer_host: host&.downcase&.first(100))
  rescue URI::InvalidURIError
    create!(referrer_host: nil)
  end
end
