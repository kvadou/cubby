# Adapted from the Rails 8.1 authentication generator for a JSON API with two credential types
# (docs/prior-art/2026-10-19-phase3-auth.md, D1 and D2):
# - web: a signed, httpOnly, SameSite=Lax cookie holding the session id
# - mobile: "Authorization: Bearer <token>", matched by SHA-256 digest
# A request that carries a bearer header is judged by it alone and never falls back to the cookie.
module Authentication
  extend ActiveSupport::Concern

  COOKIE = :session_id

  included do
    before_action :require_authentication
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  def require_authentication
    resume_session || render(json: { error: "unauthenticated" }, status: :unauthorized)
  end

  def resume_session
    Current.session ||= bearer_token.present? ? Session.find_by_bearer(bearer_token) : find_session_by_cookie
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (\S+)\z/, 1]
  end

  def find_session_by_cookie
    id = cookies.signed[COOKIE]
    Session.active.cookie.find_by(id: id) if id
  end

  def start_cookie_session_for(user)
    Current.session = user.sessions.create!(kind: "cookie", user_agent: request.user_agent, ip_address: request.remote_ip)
    cookies.signed[COOKIE] = { value: Current.session.id, expires: Current.session.expires_at,
                               httponly: true, same_site: :lax, secure: Rails.env.production? }
  end

  def terminate_session
    Current.session&.destroy
    cookies.delete(COOKIE)
  end
end
