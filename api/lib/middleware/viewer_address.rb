require "ipaddr"

# Behind CloudFront every request arrives from an edge address, so `request.remote_ip` would put all
# viewers in one rate-limit budget. CloudFront sets CloudFront-Viewer-Address ("ip:port") itself, and
# in production the load balancer is reachable only through CloudFront's VPC origin, so the header is
# trustworthy there (docs/prior-art/2026-10-19-phase6-deploy.md). Production enables this with
# CUBBY_TRUST_VIEWER_ADDRESS=1; never enable it on a host the internet can reach directly.
class ViewerAddress
  HEADER = "HTTP_CLOUDFRONT_VIEWER_ADDRESS".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    ip = self.class.parse(env[HEADER])
    env["action_dispatch.remote_ip"] = ip if ip
    @app.call(env)
  end

  # "198.51.100.10:46532" or "2001:db8::1:46532"; the port is always last. An IPv6 viewer gets its
  # whole /64, so rotating addresses inside one allocation doesn't escape per-address rate limits.
  def self.parse(value)
    host = value.to_s.rpartition(":").first
    return nil if host.empty?

    address = IPAddr.new(host)
    (address.ipv6? ? address.mask(64) : address).to_s
  rescue IPAddr::Error, ArgumentError
    nil
  end
end
