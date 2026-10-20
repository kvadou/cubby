module Api
  module V1
    # Bearer sign-in for the mobile apps. The token is returned once and only its digest is stored.
    class TokensController < BaseController
      include LoginThrottle
      allow_unauthenticated_access only: :create
      # Native apps send no Origin. Issuing a token sets no cookie, and a cross-site page cannot read
      # the response, so a forged request here gains the attacker nothing.
      skip_before_action :verify_same_origin, only: :create

      def create
        user = authenticate_from_params
        return render_invalid_login unless user

        session, token = Session.issue_bearer!(user: user, user_agent: request.user_agent, ip_address: request.remote_ip)
        Current.session = session
        render json: me_json.merge(token: token, expires_at: session.expires_at), status: :created
      end

      def destroy
        return head :not_found unless Current.session.bearer?

        Current.session.destroy
        head :no_content
      end
    end
  end
end
