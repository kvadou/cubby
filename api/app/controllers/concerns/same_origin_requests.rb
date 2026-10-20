# CSRF protection for cookie-authenticated requests, modeled on Rails 8.2's Sec-Fetch-Site strategy
# (docs/prior-art/2026-10-19-phase3-auth.md, D3). Rails 8.1 has no header strategy, and token CSRF
# needs a session store this API app does not run.
#
# Unsafe requests must come from our own origin: Sec-Fetch-Site "same-origin", or, from browsers that
# omit that header, an Origin we trust. Bearer requests are exempt because browsers never attach an
# Authorization header on their own. Replace with `protect_from_forgery` on Rails 8.2.
module SameOriginRequests
  extend ActiveSupport::Concern

  SAFE_METHODS = %w[GET HEAD OPTIONS].freeze

  included do
    before_action :verify_same_origin
  end

  private

  def verify_same_origin
    return if SAFE_METHODS.include?(request.request_method) || bearer_token.present?

    site = request.headers["Sec-Fetch-Site"]
    allowed = site.present? ? site == "same-origin" : trusted_origin?(request.headers["Origin"])
    render json: { error: "forbidden_origin" }, status: :forbidden unless allowed
  end

  def trusted_origin?(origin)
    origin.present? && (origin == request.base_url || app_origins.include?(origin))
  end

  # The web app's origins when it is served through a proxy (Vite locally, CloudFront in AWS).
  def app_origins
    ENV.fetch("APP_ORIGINS", "http://localhost:5173").split(",").map(&:strip)
  end
end
