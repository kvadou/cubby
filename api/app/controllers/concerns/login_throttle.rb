# Shared by the cookie and token sign-in endpoints so they draw on one budget (D5).
module LoginThrottle
  extend ActiveSupport::Concern

  included do
    rate_limit to: 10, within: 3.minutes, only: :create, scope: "login", name: "ip",
               with: -> { render_rate_limited }
    # Keyed on email plus IP: one address can't keep a director (or the shared demo directors) locked out
    # from everywhere, and guessing one account still needs a fresh IP every 5 tries.
    rate_limit to: 5, within: 3.minutes, only: :create, scope: "login", name: "email",
               by: -> { "#{params[:email_address].to_s.strip.downcase}|#{request.remote_ip}" }, with: -> { render_rate_limited }
    # Backstop for one account guessed from many addresses.
    rate_limit to: 50, within: 1.hour, only: :create, scope: "login", name: "account",
               by: -> { params[:email_address].to_s.strip.downcase }, with: -> { render_rate_limited }
  end

  private

  def authenticate_from_params
    email, password = params.permit(:email_address, :password).values_at(:email_address, :password)
    User.authenticate_by(email_address: email, password: password) if email.present? && password.present?
  end

  def render_invalid_login
    render json: { error: "invalid_login", message: "That email and password don't match." }, status: :unauthorized
  end

  def render_rate_limited
    render json: { error: "rate_limited", message: "Too many attempts. Try again in a few minutes." },
           status: :too_many_requests
  end
end
