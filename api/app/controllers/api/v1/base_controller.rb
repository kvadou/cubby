module Api
  module V1
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not_found" }, status: :not_found
      end

      private

      def current_center
        @current_center ||= Center.find(params[:center_id])
      end
    end
  end
end
