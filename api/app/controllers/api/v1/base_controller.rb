module Api
  module V1
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end

      private

      # Every center-scoped query starts here, so another center's data is a 404 that does not
      # reveal whether it exists (D4).
      def current_center
        @current_center ||= Current.user.centers.find(params[:center_id])
      end

      def render_invalid(message)
        render json: { error: "invalid", message: message }, status: :unprocessable_content
      end

      def me_json
        {
          user: Current.user.slice(:id, :name, :email_address),
          centers: Current.user.centers.order(:name).map { |c| c.slice(:id, :name, :city, :timezone) },
          families: Current.user.families.includes(:center).order(:id).map { |f| { id: f.id, name: f.name, center_name: f.center.name } }
        }
      end
    end
  end
end
