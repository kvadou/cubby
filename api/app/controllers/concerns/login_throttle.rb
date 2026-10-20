# Shared by the cookie and token sign-in endpoints so they draw on one budget (D5).
module LoginThrottle
  extend ActiveSupport::Concern

  included do
    rate_limit to: 10, within: 3.minutes, only: :create, scope: "login", name: "ip",
               with: -> { render_rate_limited }
    rate_limit to: 5, within: 3.minutes, only: :create, scope: "login", name: "email",
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
