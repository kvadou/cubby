require "rails_helper"
require Rails.root.join("lib/middleware/viewer_address")

RSpec.describe ViewerAddress do
  it "reads IPv4 and IPv6 viewer addresses without the port" do
    expect(described_class.parse("198.51.100.10:46532")).to eq("198.51.100.10")
    expect(described_class.parse("2001:db8::1:46532")).to eq("2001:db8::1")
  end

  it "ignores missing or malformed values" do
    expect(described_class.parse(nil)).to be_nil
    expect(described_class.parse("")).to be_nil
    expect(described_class.parse("not-an-ip:443")).to be_nil
    expect(described_class.parse("198.51.100.10")).to be_nil # no port means a value CloudFront didn't set
  end

  it "sets the remote ip Rails uses for rate limits and sessions" do
    seen = nil
    app = described_class.new(->(env) { seen = ActionDispatch::Request.new(env).remote_ip; [ 200, {}, [] ] })
    app.call(Rack::MockRequest.env_for("/", "REMOTE_ADDR" => "10.0.0.5", "HTTP_CLOUDFRONT_VIEWER_ADDRESS" => "203.0.113.7:5555"))
    expect(seen).to eq("203.0.113.7")
  end
end
