module Api
  module V1
    # One-click sign-in as the demo director, so a visitor can try the inbox without a password.
    # Exists only where Demo.enabled?; everywhere else both actions are a 404.
    class DemoSessionsController < BaseController
      allow_unauthenticated_access
      before_action :require_demo
      rate_limit to: 20, within: 1.hour, only: :create, scope: "demo", name: "ip",
                 with: -> { render json: { error: "rate_limited", message: "Too many demo sign-ins. Try again later." }, status: :too_many_requests }

      def show
        render json: { available: true, director_name: @director.name, center_name: @director.centers.first&.name }
      end

      def create
        start_cookie_session_for(@director)
        render json: me_json, status: :created
      end

      private

      def require_demo
        @director = Demo.director if Demo.enabled?
        render json: { error: "not_found" }, status: :not_found unless @director
      end
    end
  end
end
