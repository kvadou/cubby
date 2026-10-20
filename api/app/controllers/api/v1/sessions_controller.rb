module Api
  module V1
    # Cookie sign-in for the web app.
    class SessionsController < BaseController
      include LoginThrottle
      allow_unauthenticated_access only: :create

      def create
        user = authenticate_from_params
        return render_invalid_login unless user

        start_cookie_session_for(user)
        render json: me_json, status: :created
      end

      def destroy
        terminate_session
        head :no_content
      end
    end
  end
end
